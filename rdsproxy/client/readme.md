python3 storm.py rdsproxy-lab-db.cwp4qc4eqavj.us-east-1.rds.amazonaws.com 100 db

python3 storm.py rdsproxy-lab-db.cwp4qc4eqavj.us-east-1.rds.amazonaws.com 100 app



python3 storm.py rdsproxy-lab-proxy.proxy-cwp4qc4eqavj.us-east-1.rds.amazonaws.com 100 db

python3 storm.py rdsproxy-lab-proxy.proxy-cwp4qc4eqavj.us-east-1.rds.amazonaws.com 100 app





```
mysql -h rdsproxy-lab-db.cwp4qc4eqavj.us-east-1.rds.amazonaws.com -u admin -pLabPassword123

mysql -h rdsproxy-lab-proxy.proxy-cwp4qc4eqavj.us-east-1.rds.amazonaws.com -u admin -pLabPassword123


 SELECT SUBSTRING_INDEX(host, ':', 1) AS from_ip, command, COUNT(*)
  FROM information_schema.processlist
  GROUP BY from_ip, command;
```


