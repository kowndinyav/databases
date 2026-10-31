# Results

## L3 — direct to RDS (db.t4g.micro, max_connections=60), 100 workers, 10s

| mode | target | ok | failed | connect p50 | connect p99 |
|---|---|---|---|---|---|
| db  | DB direct | 1138 | 478 (1040 Too many connections) | 407 ms | 916 ms |
| app | DB direct | 1086 | 473 (1040 Too many connections) | 379 ms | 921 ms |

For reference: 20 workers direct gave 0 failures, with connect p50 38 ms and p99 270 ms.


## L4 — through RDS Proxy, 100 workers, 10s

| mode | target | ok | failed | connect p50 | connect p99 |
|---|---|---|---|---|---|
| db  | proxy | 1238 | 0 | 466 ms | 1287 ms |
| app | proxy | 1480 | 0 | 411 ms | 707 ms |

CloudWatch metrics for the minute both runs happened in (they're mixed together):
- proxy ClientConnections max 39
- proxy DatabaseConnections 27, and it stays at 27 after the runs (a warm idle pool)
- proxy DatabaseConnectionsCurrentlyBorrowed max 22, avg 19.5
- proxy DatabaseConnectionsBorrowLatency max 83 ms, avg 12.7 ms (time spent queued waiting for a DB connection)
- DB DatabaseConnections 56, which stays at 56 after the runs. This doesn't match the proxy's 27 and still needs checking.

## L6 preview — pool tuning (ConnectionBorrowTimeout=5)

- MaxConnectionsPercent=100: db mode, 100 workers → 1478 ok, 0 failed
- MaxConnectionsPercent=5: the proxy allows only 1 DB connection per node, 2 in total (`MaxDatabaseConnectionsAllowed`)
  - db mode:  171 ok, 72 failed, all `9501 Timed-out waiting to acquire database connection`
  - app mode: 618 ok / 100 failed and 417 ok / 157 failed. That's 2.5–3.6× the db-mode throughput on the same 2 DB connections.

## Single client, no concurrency (timing.py, 20 rounds)

| step | direct DB | via proxy |
|---|---|---|
| connect | ~17–25 ms | ~25–35 ms |
| SELECT 1 | ~1 ms | ~2–4 ms |
| close | ~0.2 ms | ~0.2 ms |

The proxy adds a network hop, so a single client gets slower, not faster. Its value shows up under concurrency: no 1040 errors, multiplexing, queueing.
In app mode, about 30 ms of DB-connection hold per loop (mostly connect) fits the ~42–62 req/s measured on 2 DB connections.

## Pool settings: percentages → absolute numbers

The base for every percentage is the DB's `max_connections` = **60**. The proxy runs on **2 nodes**, and each node gets half, rounded down.

| Setting | % | Total (% of 60) | Per node (÷2, round down) | Total actually allowed | Measured |
|---|---|---|---|---|---|
| MaxConnectionsPercent (default) | 100% | 60 | 30 | 60 | **27 per node, 54 total** (MaxDatabaseConnectionsAllowed). Unexplained: why not 30? |
| MaxIdleConnectionsPercent (default) | 50% | 30 | 15 | 30 | 28 idle per node seen in processlist. Unexplained: why above 15? |
| MaxConnectionsPercent (test) | 5% | 3 | 1 | **2** | 1 per node, 2 total |
| MaxIdleConnectionsPercent (test) | 5% | 3 | 1 | 2 | — |
| ConnectionBorrowTimeout | — | 5 s (absolute; default 120 s) | — | — | — |

## L5 — Pinning

- An idle `mysql` session through the proxy holds 0 DB connections (`DatabaseConnectionsCurrentlyBorrowed` = 0).
- After `SET @x = 5`, the same idle session shows `DatabaseConnectionsCurrentlySessionPinned` = 1 and `Borrowed` = 1. The DB connection is held for that client only.
- `CONNECTION_ID()` through the proxy returns the **MySQL ID of the proxy→DB connection** (its processlist host is the proxy node IP).
- After `exit`, the pinned DB connection (7131) was **not closed**. It stayed in the pool (`Sleep`).
- A later client that landed on 7131 saw `@x = NULL`, so the proxy **resets the session state** before reusing the connection. No leak.
- Two terminals landed on different proxy nodes (7131 on .92.126, 7134 on .42.150). Each node has its own pool, so they can't share.
- Debug log line for a pin: `The client session was pinned to the database connection [dbConnection=...] ... Reason: SQL changed session settings that the proxy doesn't track ... Digest: "SET @x = ?"`. `dbConnection` is the proxy's internal ID, not MySQL's CONNECTION_ID().
- Tested: `SET autocommit = 1` does not pin (the proxy tracks it).
- Takeaway: the proxy helps only if sessions stay unpinned. Detect pinning with the `DatabaseConnectionsCurrentlySessionPinned` metric and the debug logs ("pinned"). Fix it by avoiding session state or by moving settings into the proxy's InitQuery.

## L6 — IdleClientTimeout

- Set the proxy's `IdleClientTimeout` to 10 s (default 1800). Connected through the proxy, stayed idle for more than 10 s, then ran a query: `ERROR 2006 MySQL server has gone away`, and the mysql client auto-reconnected.
- There are two separate idle timeouts. The proxy's `IdleClientTimeout` applies to client→proxy. MySQL's `wait_timeout` (28800 s) applies to proxy→DB and to direct connections. `SHOW VARIABLES` only shows MySQL's.
- `Connection id: 3159476236` printed on reconnect is the proxy's client-side ID. `CONNECTION_ID()` returns MySQL's ID for the proxy→DB connection.
- For apps: keep the pool's idle/max-lifetime below `IdleClientTimeout`, or validate connections before use.

## L6 — InitQuery

- `InitQuery` is SQL the proxy runs on every **new** DB connection (part of the target group's connection-pool-config). Set it with JSON: `{"InitQuery":"SET SESSION group_concat_max_len = 100000", ...}`. Clear it with `"InitQuery":""`.
- Why it avoids pinning: pinning happens when a client's `SET` makes one DB connection different from the rest. With InitQuery every connection has the same setting from the start, so the app sends no `SET` and any client can use any connection.
- Reading a setting (`SELECT @@var`) never pins. Only changing session state does.
- The app must also **stop sending the SET**. A client `SET` would still pin, probably even with the same value (not verified).
- Turning InitQuery on or off affects only DB connections opened afterwards. Existing pooled connections keep whatever they had.
- Only works when every client wants the same value.
