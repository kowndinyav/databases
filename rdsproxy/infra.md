
## setting up AWS profile

```
export AWS_PROFILE=personal
```


## security group for RDS to allow incoming traffic on port 3306

```
SG=$(aws ec2 create-security-group \
--group-name rdsproxy-lab \
--description "rdsproxy lab" \
--vpc-id vpc-0baee361bc0126b51 \
--tag-specifications 'ResourceType=security-group,Tags=[{Key=project,Value=rdsproxy-lab}]' \
--query GroupId --output text)

aws ec2 authorize-security-group-ingress \
--group-id $SG --protocol tcp --port 3306 --source-group $SG

echo $SG
```

## ssh into ec2
```
aws ec2-instance-connect ssh --instance-id i-01487014e232d4af8 --os-user ec2-user --profile personal
```


## creating a db user for rds-proxy via secrets manager

```
aws secretsmanager create-secret --profile personal \
     --name rdsproxy-lab-db-creds \
     --secret-string '{"username":"admin","password":"LabPassword123"}' \
     --tags Key=project,Value=rdsproxy-lab \
     --query ARN --output text
arn:aws:secretsmanager:us-east-1:976456325028:secret:rdsproxy-lab-db-creds-OxJQ7J
```

## creating role to be attached to rds-proxy

```
The proxy is an AWS service, and it needs permission to read that secret. We create a role in two parts:
  1. Who can use the role (the trust policy): the RDS service, rds.amazonaws.com.
  2. What the role can do (the permission policy): read this one secret, plus decrypt it.

  Run on your laptop:

  aws iam create-role --profile personal \
    --role-name rdsproxy-lab-role \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{"Effect": "Allow", "Principal": {"Service": "rds.amazonaws.com"}, "Action": "sts:AssumeRole"}]
    }' \
    --query Role.Arn --output text

  aws iam put-role-policy --profile personal \
    --role-name rdsproxy-lab-role \
    --policy-name read-db-secret \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {"Effect": "Allow", "Action": "secretsmanager:GetSecretValue",
         "Resource": "arn:aws:secretsmanager:us-east-1:976456325028:secret:rdsproxy-lab-db-creds-OxJQ7J"},
        {"Effect": "Allow", "Action": "kms:Decrypt", "Resource": "*"}
      ]
    }'

  The first command prints the role ARN. The second prints nothing when it succeeds. Paste the role ARN.
```


  Part 3 of 3: the proxy

  This happens in two commands:
  1. Create the proxy: give it the role and secret from the previous parts, put it in our VPC with our security group, and tell it that it's talking to MySQL.
  2. Register the target: tell the proxy which database to sit in front of, rdsproxy-lab-db.

  Run on your laptop:

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

  aws rds register-db-proxy-targets --profile personal \
    --db-proxy-name rdsproxy-lab-proxy \
    --db-instance-identifiers rdsproxy-lab-db \
    --query 'DBProxyTargets[0].TargetHealth.State' --output text

  A few notes:
  - The subnets are 4 of the default VPC's subnets, in different Availability Zones. The proxy needs at least two.
  - --no-require-tls keeps things simple: our scripts connect without TLS, the same as they do to the DB today.
  - Time: creating the proxy takes about 5–15 minutes.

  The first command should print creating plus the proxy's endpoint, which is the new host you'll point storm.py at. Paste the output.





```
aws rds modify-db-proxy-target-group --profile personal \
    --db-proxy-name rdsproxy-lab-proxy \
    --target-group-name default \
    --connection-pool-config ConnectionBorrowTimeout=5 \
    --query 'DBProxyTargetGroup.ConnectionPoolConfig'
```