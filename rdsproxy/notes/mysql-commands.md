# MySQL commands used in the RDS Proxy lab

## Connecting

```bash
# local Docker MySQL (L1)
docker exec -it rdsproxy-l1-mysql mysql -uroot -proot

# RDS directly
mysql -h rdsproxy-lab-db.cwp4qc4eqavj.us-east-1.rds.amazonaws.com -u admin -pLabPassword123

# through RDS Proxy (same user/password, only the host changes)
mysql -h rdsproxy-lab-proxy.proxy-cwp4qc4eqavj.us-east-1.rds.amazonaws.com -u admin -pLabPassword123

# run one statement and exit (-e)
mysql -h <host> -u admin -pLabPassword123 -e "SET autocommit = 1"
```

---

## Connection limits and who's connected

```sql
-- max connections allowed (RDS db.t4g.micro → 60)
SELECT @@max_connections;

-- connection counters: connected / created / running
SHOW GLOBAL STATUS LIKE 'Threads_%';

-- what every connection is doing (Sleep = idle, Query = running)
SHOW PROCESSLIST;

-- who is connected, grouped by source IP and state
-- (on RDS: proxy node IPs, the EC2 client, localhost = RDS internal)
SELECT SUBSTRING_INDEX(host, ':', 1) AS from_ip, command, COUNT(*)
FROM information_schema.processlist
GROUP BY from_ip, command;

-- look up specific connection IDs (which proxy node owns them, alive or not)
SELECT id, SUBSTRING_INDEX(host, ':', 1) AS proxy_node_ip, command, time
FROM information_schema.processlist
WHERE id IN (7131, 7134);
```

## Per-connection memory (L1, local)

```sql
-- buffers each connection can allocate
SELECT @@thread_stack, @@sort_buffer_size, @@join_buffer_size, @@net_buffer_length;

-- memory currently used per connection thread
SELECT t.PROCESSLIST_ID, sys.format_bytes(SUM(m.CURRENT_NUMBER_OF_BYTES_USED)) AS mem
FROM performance_schema.memory_summary_by_thread_by_event_name m
JOIN performance_schema.threads t USING (THREAD_ID)
WHERE t.PROCESSLIST_ID IS NOT NULL
GROUP BY t.PROCESSLIST_ID
ORDER BY SUM(m.CURRENT_NUMBER_OF_BYTES_USED) DESC
LIMIT 10;
```

---

## Workload queries (used by the scripts)

```sql
SELECT 1;            -- trivial query (~1 ms direct, ~2–4 ms via proxy)
SELECT SLEEP(0.2);   -- keeps the connection BUSY inside MySQL for 200 ms (storm.py db mode)
```

---

## Which DB connection am I on?

```sql
-- returns MySQL's ID for the connection the query arrived on.
-- Through the proxy, that's the proxy→DB connection, NOT your client→proxy one.
SELECT CONNECTION_ID();

-- connection ID + a session variable together (check reset after pinning)
SELECT CONNECTION_ID(), @x;
```

---

## Pinning (L5)

```sql
-- pins (user variable lives on the DB connection; proxy doesn't track it)
SET @x = 5;
SELECT @x;

-- does NOT pin (tracked by the proxy)
SET autocommit = 1;
SET NAMES utf8mb4;          -- pymysql sends this automatically on every connect

-- other candidates we listed (not all tested)
SET time_zone = '+00:00';
SET SESSION sql_mode = 'ANSI';
CREATE TEMPORARY TABLE t (i INT);
SELECT GET_LOCK('mylock', 1);
BEGIN; SELECT 1; COMMIT;    -- a normal transaction, no pinning
```

## InitQuery (L6)

```sql
-- the setting we moved into the proxy's InitQuery
SET SESSION group_concat_max_len = 100000;

-- check the value (reading never pins). 1024 = MySQL default, 100000 = InitQuery applied
SELECT CONNECTION_ID(), @@group_concat_max_len;
```

## Timeouts (L6)

```sql
-- MySQL's own idle timeout (proxy→DB and direct connections), default 28800 s = 8 h.
-- The proxy's IdleClientTimeout is NOT visible here; it lives in AWS.
SHOW VARIABLES LIKE 'wait_timeout';
```

---

## Not run, but mentioned

```sql
-- per-user connection cap in MySQL (an alternative way to limit one app)
ALTER USER 'appA' WITH MAX_USER_CONNECTIONS 6;
```
