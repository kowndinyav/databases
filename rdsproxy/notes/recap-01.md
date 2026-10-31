# Recap of experiments so far

Terms:
- **cold**: open a new connection for every request. **warm**: connect once and reuse the connection.
- **db-busy**: `SELECT SLEEP(0.2)`, so MySQL is busy for 200 ms. **app-idle**: `SELECT 1`, then a 200 ms sleep in Python, so the connection is idle.
- RDS = db.t4g.micro, `max_connections` = 60. Proxy = 2 nodes.

| # | Experiment | Client config | DB / proxy config | Expected | Observed |
|---|---|---|---|---|---|
| 1 | Cost of connecting (local) | 1 client, cold vs warm, `SELECT 1` × 200 | Local Docker MySQL, max_conn 20 | Connecting costs much more than the query | cold 8.04 ms/query, warm 0.26 ms/query (**~31×**) |
| 2 | Hit the connection limit (local) | 1 process opens and holds 30 idle connections | Local Docker MySQL, max_conn 20 | Fails after 20 | #22 failed with `1040`; 21 succeeded because root gets the spare admin slot |
| 3 | RDS connection limit | `mysql` CLI | RDS direct | ~60–80 | `max_connections` = **60** |
| 4 | Storm, under the limit | 20 workers, cold, db-busy | RDS direct | 0 failures | 806 ok / **0 failed**; connect p50 38 ms, p99 270 ms |
| 5 | Storm, over the limit | 100 workers, cold, db-busy | RDS direct | Failures | 1138 ok / **478 failed** (`1040`); connect p50 407 ms |
| 6 | Storm, idle connections | 100 workers, cold, app-idle | RDS direct | Same as #5 (open connections still count) | 1086 ok / **473 failed** (`1040`) ✅ |
| 7 | Proxy, DB busy | 100 workers, cold, db-busy | Proxy: 100% / idle 50% / timeout 120 s | Fewer errors, slower | 1238 ok / **0 failed**; borrow wait max 83 ms |
| 8 | Proxy, idle connections | 100 workers, cold, app-idle | Proxy: 100% / 50% / 120 s | ~0 failures | 1480 ok / **0 failed** ✅; max 22 DB connections in use; proxy kept 56 idle on DB |
| 9 | Proxy, shorter timeout | 100 workers, cold, db-busy | Proxy: 100% / 50% / **5 s** | Still 0 failures (waits ≪ 5 s) | 1478 ok / **0 failed** ✅ |
| 10 | Proxy, tiny pool, DB busy | 100 workers, cold, db-busy | Proxy: **5% (= 2 DB connections)** / 5% / 5 s | Timeouts | 171 ok / **72 failed** (`9501` timed out) ✅ |
| 11 | Proxy, tiny pool, idle | 100 workers, cold, app-idle | Proxy: 5% (2 conns) / 5% / 5 s | ~0 failures | 618 ok / **100 failed**, 417 ok / **157 failed** (`9501`) ❌ prediction wrong |
| 12 | Single request timing | 1 client, cold, `SELECT 1` × 20 | RDS direct vs proxy (5% pool) | Proxy connect cheaper | connect: direct 17–25 ms, proxy 25–35 ms; SELECT 1: direct ~1 ms, proxy 2–4 ms ❌ prediction wrong: the proxy adds a hop |
| 13 | `SELECT 1` by hand | `mysql` CLI, 1 session | Proxy (5% pool) | — | 2 ms |
| 14 | Warm connections, tiny pool | 100 workers, **warm**, app-idle | Proxy: 5% (2 conns) / 5% / 5 s | ~0 failures, ~4500 ok | 354 ok / **100 failed**, 359 ok / **100 failed** (`9501`) ❌ prediction wrong, not yet explained |

*From here on the pool is restored to 90% / 50% / 120 s, which is 54 DB connections total, 27 per node.*

| # | Experiment | Client config | DB / proxy config | Expected | Observed |
|---|---|---|---|---|---|
| 15 | Which DB connection am I on? | 1 `mysql` session, `SELECT CONNECTION_ID()` × 5 | Proxy 90/50/120 | Might change (sharing) | Always **7131**. Inconclusive: when you're the only client, the proxy just reuses the same idle connection |
| 16 | Do two clients share one DB connection? | 2 `mysql` sessions (2 terminals) | Proxy 90/50/120 | Same ID in both | **7131 vs 7134**. They were on **different proxy nodes** (.92.126 vs .42.150), and each node has its own pool, so they can't share. Inconclusive; sharing was already proven in #8 |
| 17 | Pin a connection | 1 `mysql` session, `SET @x = 5`, then idle | Proxy 90/50/120 | Pinned = 1 | Before: Borrowed 0. After: **SessionPinned = 1, Borrowed = 1** while idle ✅ |
| 18 | What happens to the pinned DB connection after `exit`? | `SET @x = 5`, note ID (7131), `exit` | Proxy 90/50/120 | Closed or reset? | 7131 **still alive** (`Sleep`), so it was kept in the pool |
| 19 | Does the next client see `@x`? | Reconnect until landing on 7131, `SELECT @x` | Proxy 90/50/120 | `NULL` (no leak) | `@x = NULL` ✅. The proxy **resets session state** before reusing the connection |

## What we've learned (L1–L5 so far)
- Connections are expensive (~31× a query) and limited (60 on db.t4g.micro). Idle connections still use up the limit.
- The proxy removes `1040 Too many connections` errors by sharing a few DB connections among many clients.
- The proxy **queues** requests rather than creating capacity. Too small a pool or too short a `ConnectionBorrowTimeout` gives `9501` timeouts.
- For a single request, the proxy adds a hop (+~10 ms connect, +~2 ms query). Its value shows up under concurrency.
- Pool percentages are of `max_connections`, split across proxy nodes and rounded down.
- One proxy has one pool. For per-app limits, use a separate proxy per app.
- **Pinning:** session state (e.g. `SET @x`) ties a DB connection to one client until it disconnects. After that, the proxy resets the connection and reuses it.

Open questions are in [parked-questions.md](parked-questions.md).
