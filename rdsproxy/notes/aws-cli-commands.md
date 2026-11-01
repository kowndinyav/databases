# AWS CLI commands used in the RDS Proxy lab

All commands use `--profile personal` (account 976456325028, us-east-1).
IDs are saved in `../lab.env` (`source lab.env`).

| Thing | ID / name |
|---|---|
| VPC (default) | `vpc-0baee361bc0126b51` |
| Security group | `sg-0eea17e7b82e31453` (`rdsproxy-lab`) |
| EC2 client | `i-01487014e232d4af8` (`rdsproxy-lab-client`) |
| RDS DB | `rdsproxy-lab-db` → `rdsproxy-lab-db.cwp4qc4eqavj.us-east-1.rds.amazonaws.com` |
| Secret | `rdsproxy-lab-db-creds` |
| IAM role | `rdsproxy-lab-role` |
| Proxy | `rdsproxy-lab-proxy` → `rdsproxy-lab-proxy.proxy-cwp4qc4eqavj.us-east-1.rds.amazonaws.com` (deleted 2026-11-01) |

---

## 1. Identity / environment

```bash
# who am I? (verify the profile works)
aws sts get-caller-identity --profile personal

# default VPC
aws ec2 describe-vpcs --profile personal --filters Name=isDefault,Values=true \
  --query 'Vpcs[].VpcId' --output text

# subnets of the default VPC (the proxy needs 2+ AZs)
aws ec2 describe-subnets --profile personal --filters Name=vpc-id,Values=vpc-0baee361bc0126b51 \
  --query 'Subnets[].[SubnetId,AvailabilityZone]' --output text
```

## 2. Security group

```bash
# create
aws ec2 create-security-group --profile personal \
  --group-name rdsproxy-lab --description "rdsproxy lab" \
  --vpc-id vpc-0baee361bc0126b51 \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=project,Value=rdsproxy-lab}]' \
  --query GroupId --output text

# MySQL (3306) allowed from anything with the same SG (DB, EC2, proxy)
aws ec2 authorize-security-group-ingress --profile personal \
  --group-id sg-0eea17e7b82e31453 --protocol tcp --port 3306 --source-group sg-0eea17e7b82e31453

# SSH (22) from anywhere
aws ec2 authorize-security-group-ingress --profile personal \
  --group-id sg-0eea17e7b82e31453 --protocol tcp --port 22 --cidr 0.0.0.0/0

# list inbound rules
aws ec2 describe-security-groups --profile personal --group-ids sg-0eea17e7b82e31453 \
  --query 'SecurityGroups[0].IpPermissions[].[FromPort,IpRanges[].CidrIp|join(`,`,@),UserIdGroupPairs[].GroupId|join(`,`,@)]' \
  --output text
```

## 3. RDS MySQL

```bash
# which MySQL versions are available (8.0 is past standard support → extra cost)
aws rds describe-db-engine-versions --profile personal --engine mysql --default-only \
  --query 'DBEngineVersions[].EngineVersion' --output text

# create the DB
aws rds create-db-instance --profile personal \
  --db-instance-identifier rdsproxy-lab-db \
  --engine mysql --engine-version 8.4 \
  --db-instance-class db.t4g.micro \
  --allocated-storage 20 \
  --master-username admin --master-user-password LabPassword123 \
  --vpc-security-group-ids sg-0eea17e7b82e31453 \
  --no-publicly-accessible \
  --backup-retention-period 0 \
  --tags Key=project,Value=rdsproxy-lab \
  --query 'DBInstance.DBInstanceStatus'

# status + endpoint
aws rds describe-db-instances --profile personal --db-instance-identifier rdsproxy-lab-db \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address]' --output text

# (L7, not run) convert to Multi-AZ
aws rds modify-db-instance --profile personal \
  --db-instance-identifier rdsproxy-lab-db --multi-az --apply-immediately \
  --query 'DBInstance.PendingModifiedValues'
```

## 4. EC2 client

```bash
# launch (AL2023 arm64, t4g.micro, same SG)
aws ec2 run-instances --profile personal \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
  --instance-type t4g.micro \
  --security-group-ids sg-0eea17e7b82e31453 \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=project,Value=rdsproxy-lab},{Key=Name,Value=rdsproxy-lab-client}]' \
  --query 'Instances[0].InstanceId' --output text

# SSH in (pushes a temporary key, no key pair needed)
aws ec2-instance-connect ssh --profile personal --instance-id i-01487014e232d4af8 --os-user ec2-user

# which resource owns an IP? (used to identify proxy nodes in processlist)
aws ec2 describe-network-interfaces --profile personal \
  --filters Name=addresses.private-ip-address,Values=172.31.42.150,172.31.92.126 \
  --query 'NetworkInterfaces[].[PrivateIpAddress,AvailabilityZone,Description]' --output text
```

On the EC2 box (not AWS CLI):
```bash
sudo dnf install -y mariadb105                       # mysql client
sudo dnf install -y python3-pip && pip3 install pymysql
```

## 5. Secret + IAM role (what the proxy needs)

```bash
# DB credentials in Secrets Manager
aws secretsmanager create-secret --profile personal \
  --name rdsproxy-lab-db-creds \
  --secret-string '{"username":"admin","password":"LabPassword123"}' \
  --tags Key=project,Value=rdsproxy-lab \
  --query ARN --output text

# role the proxy assumes
aws iam create-role --profile personal \
  --role-name rdsproxy-lab-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "rds.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }' \
  --query Role.Arn --output text

# permission to read the secret
aws iam put-role-policy --profile personal \
  --role-name rdsproxy-lab-role --policy-name read-db-secret \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {"Effect": "Allow", "Action": "secretsmanager:GetSecretValue",
       "Resource": "arn:aws:secretsmanager:us-east-1:976456325028:secret:rdsproxy-lab-db-creds-OxJQ7J"},
      {"Effect": "Allow", "Action": "kms:Decrypt", "Resource": "*"}
    ]
  }'
```

## 6. RDS Proxy

```bash
# create
aws rds create-db-proxy --profile personal \
  --db-proxy-name rdsproxy-lab-proxy \
  --engine-family MYSQL \
  --auth '[{"AuthScheme":"SECRETS","SecretArn":"arn:aws:secretsmanager:us-east-1:976456325028:secret:rdsproxy-lab-db-creds-OxJQ7J","IAMAuth":"DISABLED"}]' \
  --role-arn arn:aws:iam::976456325028:role/rdsproxy-lab-role \
  --vpc-subnet-ids subnet-0c7e4ebdc3015828b subnet-0f8543c1f61b3dee8 subnet-0831e9429e36631f1 subnet-09a6c485ac3993335 \
  --vpc-security-group-ids sg-0eea17e7b82e31453 \
  --no-require-tls \
  --tags Key=project,Value=rdsproxy-lab \
  --query 'DBProxy.[Status,Endpoint]' --output text

# register the DB as the target (goes into the "default" target group)
aws rds register-db-proxy-targets --profile personal \
  --db-proxy-name rdsproxy-lab-proxy --db-instance-identifiers rdsproxy-lab-db \
  --query 'DBProxyTargets[0].TargetHealth.State' --output text

# proxy status
aws rds describe-db-proxies --profile personal --db-proxy-name rdsproxy-lab-proxy \
  --query 'DBProxies[0].Status' --output text

# target health (+ reason, e.g. PENDING_PROXY_CAPACITY, AUTH_FAILURE, CONNECTION_FAILED)
aws rds describe-db-proxy-targets --profile personal --db-proxy-name rdsproxy-lab-proxy \
  --query 'Targets[0].TargetHealth'

# read the proxy's IdleClientTimeout
aws rds describe-db-proxies --profile personal --db-proxy-name rdsproxy-lab-proxy \
  --query 'DBProxies[0].IdleClientTimeout'

# read the pool config
aws rds describe-db-proxy-target-groups --profile personal --db-proxy-name rdsproxy-lab-proxy \
  --query 'TargetGroups[0].ConnectionPoolConfig'

# delete
aws rds delete-db-proxy --profile personal --db-proxy-name rdsproxy-lab-proxy --query 'DBProxy.Status'
```

### Proxy settings (modify-db-proxy)

```bash
# debug logging on (logs pinning reasons; also logs SQL text, don't leave on in prod)
aws rds modify-db-proxy --profile personal --db-proxy-name rdsproxy-lab-proxy \
  --debug-logging --query 'DBProxy.DebugLogging'

# idle client timeout (seconds; default 1800)
aws rds modify-db-proxy --profile personal --db-proxy-name rdsproxy-lab-proxy \
  --idle-client-timeout 10 --query 'DBProxy.IdleClientTimeout'
```

### Pool settings (modify-db-proxy-target-group)

```bash
# normal
aws rds modify-db-proxy-target-group --profile personal \
  --db-proxy-name rdsproxy-lab-proxy --target-group-name default \
  --connection-pool-config MaxConnectionsPercent=90,MaxIdleConnectionsPercent=50,ConnectionBorrowTimeout=120 \
  --query 'DBProxyTargetGroup.ConnectionPoolConfig'

# tiny pool (5% of 60 → 1 per node → 2 total) + short wait
aws rds modify-db-proxy-target-group --profile personal \
  --db-proxy-name rdsproxy-lab-proxy --target-group-name default \
  --connection-pool-config MaxConnectionsPercent=5,MaxIdleConnectionsPercent=5,ConnectionBorrowTimeout=5 \
  --query 'DBProxyTargetGroup.ConnectionPoolConfig'

# InitQuery (JSON form, because the SQL has spaces and '=')
aws rds modify-db-proxy-target-group --profile personal \
  --db-proxy-name rdsproxy-lab-proxy --target-group-name default \
  --connection-pool-config '{"MaxConnectionsPercent":90,"MaxIdleConnectionsPercent":50,"ConnectionBorrowTimeout":120,"InitQuery":"SET SESSION group_concat_max_len = 100000"}' \
  --query 'DBProxyTargetGroup.ConnectionPoolConfig'

# clear InitQuery
aws rds modify-db-proxy-target-group --profile personal \
  --db-proxy-name rdsproxy-lab-proxy --target-group-name default \
  --connection-pool-config '{"MaxConnectionsPercent":90,"MaxIdleConnectionsPercent":50,"ConnectionBorrowTimeout":120,"InitQuery":""}' \
  --query 'DBProxyTargetGroup.ConnectionPoolConfig'
```

## 7. CloudWatch metrics

Proxy metrics are in namespace `AWS/RDS` with dimension `ProxyName`. Use **Sum** for counts across the proxy, because there are several datapoints per minute (e.g. one per node).

```bash
# generic: change --metric-name / --start-time as needed
aws cloudwatch get-metric-statistics --profile personal \
  --namespace AWS/RDS --metric-name QueryRequests \
  --dimensions Name=ProxyName,Value=rdsproxy-lab-proxy \
  --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Sum Maximum Minimum SampleCount \
  --query 'sort_by(Datapoints,&Timestamp)[?Sum>`0`].[Timestamp,SampleCount,Minimum,Maximum,Sum]' \
  --output text

# DB-side connections (dimension DBInstanceIdentifier)
aws cloudwatch get-metric-statistics --profile personal \
  --namespace AWS/RDS --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=rdsproxy-lab-db \
  --start-time $(date -u -v-20M +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 --statistics Maximum \
  --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Maximum]' --output text
```

Proxy metrics we used:

| Metric | Meaning |
|---|---|
| `ClientConnections` | client → proxy connections |
| `DatabaseConnections` | proxy → DB connections |
| `MaxDatabaseConnectionsAllowed` | pool cap (per node) |
| `DatabaseConnectionsCurrentlyBorrowed` | DB connections lent out right now |
| `DatabaseConnectionsCurrentlySessionPinned` | pinned DB connections |
| `DatabaseConnectionsBorrowLatency` | time waiting for a DB connection (**microseconds**) |
| `DatabaseConnectionRequests` / `DatabaseConnectionsSetupSucceeded` | new DB connections opened by the proxy |
| `ClientConnectionsReceived` | new client connections |
| `QueryRequests` | queries received from clients |
| `QueryDatabaseResponseLatency` | time MySQL took (µs) |
| `QueryResponseLatency` | time the client saw, including queue wait (µs) |

## 8. CloudWatch Logs (proxy debug logs)

```bash
# pinning events in the last 5 minutes
aws logs tail /aws/rds/proxy/rdsproxy-lab-proxy --profile personal --since 5m --filter-pattern pinned
```
