# RDS Proxy — Flashcards

Cover the answer, say yours out loud, then check.

---

### 1. Why is `max_connections` limited (60 on db.t4g.micro)? Why not 10,000?
<details><summary>Answer</summary>

Each MySQL connection is a **thread with its own memory** (stack, sort/join/net buffers).
RDS sets the limit from RAM: `max_connections = DBInstanceClassMemory / 12582880` (~12 MB per connection). 1 GB of RAM gives ~60.
It's just a parameter and you *can* raise it, but too many connections exhaust memory and the DB slows down or crashes. **The real limit is memory per connection.**
</details>

---

### 2. Without a proxy, 100 workers ran `SELECT 1` and then slept 200 ms in Python. MySQL was barely working, yet ~30% got `1040 Too many connections`. Why?
<details><summary>Answer</summary>

MySQL counts **open** connections, not **busy** ones. Each worker held its connection open for the whole loop, so ~100 were open against a limit of 60, even though each was busy for only ~1 ms.
</details>

---

### 3. With RDS Proxy in front, the same 100 workers got 0 errors. What did the proxy do?
<details><summary>Answer</summary>

**Multiplexing.** There are two kinds of connections:
- **client → proxy**: many (all 100), and they cost MySQL nothing
- **proxy → DB**: few and shared. Only these count against the 60.

The proxy lends a DB connection only for the duration of a **transaction**. With autocommit, that means each statement, so it's returned right after `SELECT 1`. Inside `BEGIN…COMMIT`, it's held until `COMMIT`.
</details>

---

### 4. `1040 Too many connections` vs `9501 Timed-out waiting to acquire database connection`: who raises each, and when? Which two settings produce 9501?
<details><summary>Answer</summary>

| | 1040 | 9501 |
|---|---|---|
| Raised by | **MySQL** | **the proxy** |
| When | **immediately**, when the connection would go over `max_connections` | after **waiting in the queue** for `ConnectionBorrowTimeout` |

9501 needs a **small pool** (`MaxConnectionsPercent`) **plus** a **short wait** (`ConnectionBorrowTimeout`). At the 120 s default, clients just wait longer instead of failing.
**MySQL rejects; the proxy queues.**
</details>

---

### 5. `MaxConnectionsPercent = 5`, `max_connections = 60`, the proxy has 2 nodes. How many DB connections can the proxy actually open?
<details><summary>Answer</summary>

5% of 60 = 3, split across 2 nodes = 1.5 each, **rounded down to 1 per node**, so **2 in total** (`MaxDatabaseConnectionsAllowed` = 1 per node).
Lesson: with small percentages, rounding per node takes away a big share (you asked for 3 and got 2).
</details>

---

### 6. Through the proxy you run `SET @x = 5` and then go idle. What happens to the DB connection behind your session? What happens when you disconnect?
<details><summary>Answer</summary>

**Pinning.** `@x` lives on the MySQL (proxy → DB) connection, so the proxy can't lend it to anyone else. You hold 1 DB connection exclusively, even while idle (`SessionPinned = 1`, `Borrowed = 1`).
When you disconnect, the proxy **resets** the connection (clears `@x`) and returns it to the pool. The next client sees `@x = NULL`.
</details>

---

### 7. Every request runs `SET SESSION group_concat_max_len = 100000`. What's the problem behind RDS Proxy, and what's the fix (two parts)?
<details><summary>Answer</summary>

Problem: an untracked `SET` → **pinning** → no sharing.
Fix:
1. Put it in the proxy's **`InitQuery`**, so every DB connection has it from the start.
2. **Remove the `SET` from the app.** If the app still sends it, it **still pins**, even with the same value.

(`InitQuery` only works when every client wants the same value.)
</details>

---

### 8. For a single request on its own, is the proxy faster or slower than going direct? Does the proxy save connect time?
<details><summary>Answer</summary>

**Slower.** It adds a hop. Measured: connect 17–25 ms direct vs 25–35 ms through the proxy; `SELECT 1` ~1 ms vs 2–4 ms.
It does **not** save client connect time: the client still does a full handshake (TCP + auth + driver `SET NAMES`) with the proxy. The warm pool saves **MySQL** the work of creating threads and authenticating, not your client's latency.
**The proxy's value shows up under concurrency, not for a single request.**
</details>

---

### 9. Apps A and B share one DB through one proxy. Can you cap app A at 10% of DB connections?
<details><summary>Answer</summary>

**Not inside one proxy.** One proxy has one pool and no per-app limits.
Use **one proxy per app**, each with its own `MaxConnectionsPercent`. Both are percentages of the **same** `max_connections`, so leave headroom for direct/admin connections (e.g. 10% + 80%, not 10% + 90%).
</details>

---

### 10. Idle through the proxy, you got `ERROR 2006 MySQL server has gone away`, but `wait_timeout` = 28800. Which timeout fired, and why didn't `SHOW VARIABLES` show it?
<details><summary>Answer</summary>

The proxy's **`IdleClientTimeout`** fired. `SHOW VARIABLES` is answered by **MySQL** and only shows MySQL's settings. The proxy's settings live in AWS (`aws rds describe-db-proxies`).
There are two timeouts on two connections:
- `IdleClientTimeout` → client ↔ proxy
- `wait_timeout` → proxy ↔ DB (and direct connections)
</details>

---

## Bonus cards

### 11. Through the proxy, `SELECT CONNECTION_ID()` returns 7131. Which connection is that: client→proxy or proxy→DB?
<details><summary>Answer</summary>

**proxy → DB.** The query is executed by MySQL, which returns the ID of the connection the query arrived on. MySQL never sees the client→proxy connection.
(The `Connection id: 3159476236` printed by the mysql client on reconnect is the **proxy's** client-side ID.)
</details>

### 12. Your script runs 1 query per loop, but the proxy's `QueryRequests` shows 2 per loop. What's going on?
<details><summary>Answer</summary>

The **driver** sends statements you never wrote: pymysql sends `SET NAMES utf8mb4` on **every connect**. It's harmless here (the proxy tracks charset, so it doesn't pin), but an untracked `SET` from a driver or ORM would pin **every** connection.
That's why it's worth knowing what your driver sends (debug logs / a spy).
</details>

### 13. After a Multi-AZ failover, why do direct clients see a long outage, and why does the proxy shorten it?
<details><summary>Answer</summary>

Failover moves the primary, and RDS updates the **DB's DNS name**. Direct clients keep connecting to the **old cached IP** until DNS caches expire.
With the proxy, the app's DNS name (the proxy's) **doesn't change**, and the proxy learns about the new primary **from RDS directly**, without depending on the DB's DNS.
</details>

### 14. How do you detect pinning in production?
<details><summary>Answer</summary>

- CloudWatch metric **`DatabaseConnectionsCurrentlySessionPinned`**
- Proxy **debug logs**: lines containing "pinned", with a `Reason` and a `Digest` (the statement that caused it)
</details>

### 15. `MaxIdleConnectionsPercent`: is it in addition to `MaxConnectionsPercent`?
<details><summary>Answer</summary>

**No, it's part of it.** Both are % of `max_connections`. Idle is the most of the allowed connections the proxy may keep open while unused, so it must be ≤ `MaxConnectionsPercent`.
</details>
