# Learning AWS RDS Proxy — from first principles, by doing

Engine: **MySQL 8.4** (RDS for MySQL; 8.0 is past standard support and costs extra).
Infra: plain **AWS CLI bash scripts**, one per lesson, so you can see every resource being created. Each lesson has a matching teardown.
Region: `us-east-1`.

---

## Part 1 — The problem (why RDS Proxy exists)

A database connection is expensive. RDS Proxy exists because of what follows from that:

| # | First principle | What breaks | How RDS Proxy fixes it |
|---|---|---|---|
| P1 | Opening a connection costs a TCP handshake, a TLS handshake and MySQL auth, which adds up to several round trips | Short-lived clients (Lambda, PHP, cron jobs) spend more time connecting than querying | Clients connect to the proxy; the proxy keeps warm connections to the DB |
| P2 | Each MySQL connection is a server **thread** with its own buffers (thread stack, sort/join/read buffers, net buffer). RDS sets `max_connections` from instance memory, and a `db.t4g.micro` gets about 60–80 | Many clients means `ERROR 1040: Too many connections` | **Multiplexing**: many client connections share a few DB connections |
| P3 | Most connections sit idle (`Sleep` in `SHOW PROCESSLIST`) most of the time | Idle connections still use memory and slots | A DB connection is borrowed only for the length of a transaction |
| P4 | Clients can scale up much faster than the DB (autoscaling, Lambda bursts) | Connection storms take down the DB; the thread-creation rate becomes the bottleneck | The proxy queues requests (`ConnectionBorrowTimeout`) and caps DB connections (`MaxConnectionsPercent`) |
| P5 | On failover the DB endpoint's DNS changes and clients cache it | 30–60s+ of errors after a Multi-AZ failover | The proxy keeps the client connections open and reconnects to the new primary itself |
| P6 | Passwords end up inside app config | Secret sprawl | The proxy reads credentials from Secrets Manager; clients can use IAM auth |

Two catches to learn as well:
- **Pinning**: session state ties a client to one DB connection, which cancels the multiplexing benefit. In MySQL the triggers include `SET` of session variables, user variables (`@x`), temporary tables, `GET_LOCK()`, `LOCK TABLES` and text-protocol `PREPARE`.
- The proxy is **reachable only from inside the VPC**, so we need a client machine (EC2) inside the VPC.

---

## Part 2 — Lessons (small chunks, about 20–40 min each)

### L0 — Setup (10 min)
- AWS CLI working, plus a project tag (`project=rdsproxy-lab`) so we can find and delete everything later.

### L1 — Feel the cost of a connection, locally and for free (P1, P2, P3)
- Run MySQL 8.0 in Docker with `max_connections=20`.
- Python script (`pymysql`): time `connect()` against `SELECT 1`.
- Open 30 connections and watch `Threads_connected`, `Threads_created` and `SHOW PROCESSLIST` (lots of `Sleep`), then hit `ERROR 1040`.
- Look at per-connection memory in `performance_schema.memory_summary_by_thread_by_event_name`.
- **Outcome:** you've seen the problem with your own eyes before spending any money on AWS.

### L2 — Base AWS lab (no proxy yet)
- Default VPC, one security group (self-referencing on port 3306).
- RDS MySQL 8.4 `db.t4g.micro`, Single-AZ.
- EC2 `t4g.micro` client in the same VPC (access through SSM Session Manager, no SSH keys), with Python and the `mysql` client installed.
- Check `SELECT @@max_connections;` and compare it with the RDS formula `{DBInstanceClassMemory/12582880}`.

### L3 — Reproduce the connection storm on RDS (P2, P4)
- `storm.py`: N concurrent workers, each runs connect → query → disconnect in a loop.
- Increase N until `ERROR 1040` starts. Watch CloudWatch `DatabaseConnections`, `FreeableMemory` and `CPUUtilization`.
- Measure p50/p99 latency, including connect time.

### L4 — Add RDS Proxy and rerun the same storm
- Secrets Manager secret, IAM role for the proxy, the proxy itself, and target registration.
- Point `storm.py` at the proxy endpoint, changing nothing else.
- Compare proxy `ClientConnections` with `DatabaseConnections`. That gap is multiplexing.
- Compare connect latency (TLS to the proxy, but no new MySQL thread or auth).

### L5 — Pinning: when the proxy can't help (the catch)
- Turn on proxy debug logging.
- Run sessions that do `SET SESSION sql_mode=...`, `SET @x=1`, `CREATE TEMPORARY TABLE` and `SELECT GET_LOCK(...)`.
- Watch `DatabaseConnectionsCurrentlySessionPinned` and the "pinned" lines in the logs.
- Find out which `SET`s the proxy tracks *without* pinning (e.g. `autocommit`, `time_zone`, `character set`), and which ones pin.
- Learn the rule: set state through the proxy's init query, or avoid session state.

### L6 — Tuning knobs (P4)
- Set `MaxConnectionsPercent` low (for example 10%) and reproduce borrow-timeout errors.
- Change `ConnectionBorrowTimeout`, `MaxIdleConnectionsPercent`, `IdleClientTimeout` and `InitQuery`.
- **Outcome:** you see that the proxy queues load rather than removing it.

### L7 — Failover (P5)
- Convert the DB to Multi-AZ.
- A probe script inserts a row every 100 ms, against the DB endpoint and against the proxy endpoint.
- `reboot-db-instance --force-failover`, then compare the outage windows.

### L8 (optional) — IAM authentication to the proxy (P6)
- Client connects with an IAM token instead of a password.

### L9 (optional) — The real-world case: Lambda
- A Lambda in the VPC that opens a connection per invocation. Burst it with concurrency, without and then with the proxy.

### L10 — Teardown
- Delete everything tagged `project=rdsproxy-lab` and confirm the bill stops.

---

## Cost (rough, us-east-1)
- RDS `db.t4g.micro`: about $0.016/hr
- RDS Proxy: billed per vCPU of the DB, minimum 2 vCPU, about $0.03/hr
- EC2 `t4g.micro`: about $0.008/hr
- Multi-AZ (L7) doubles the DB cost.

That comes to about **$0.06/hr, or about $1.50/day** if left running. Tear down between sessions if you'll be away for days. Recreating the stack takes about 15 minutes.

## Folder layout (built as we go)
```
rdsproxy/
  PLAN.md
  notes/           # your notes per lesson
  local/           # L1 docker + scripts
  infra/           # aws cli scripts: 02_base.sh, 04_proxy.sh, ..., 99_teardown.sh
  client/          # storm.py, probe.py, pinning.py
```
