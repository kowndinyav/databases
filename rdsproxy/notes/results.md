# Results

## L3 — direct to RDS (db.t4g.micro, max_connections=60), 100 workers, 10s

| mode | target | ok | failed | connect p50 | connect p99 |
|---|---|---|---|---|---|
| db  | DB direct | 1138 | 478 (1040 Too many connections) | 407 ms | 916 ms |
| app | DB direct | 1086 | 473 (1040 Too many connections) | 379 ms | 921 ms |

For reference: 20 workers direct gave 0 failures, with connect p50 38 ms and p99 270 ms.
