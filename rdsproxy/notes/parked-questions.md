# Parked questions (revisit later)

1. **Tiny-pool throughput.** With only 2 DB connections (5% pool), 100 app-idle workers got just ~35–60 requests/s, both cold (recap-01 #11) and warm (#14). MySQL answers `SELECT 1` in ~1 ms (`QueryDatabaseResponseLatency`), so where do the other ~30–50 ms per request go inside the proxy?
   - Idea to check: proxy debug logs, and whether moving a DB connection from one client to another costs time.
   - **New evidence (2026-10-31), pool 5% (2 DB conns), timeout 120 s:** warm.py 409 ok / 0 failed; storm.py app 735 ok / 0 failed (connect p99 8.2 s).
     **Warm did LESS work than cold.** That goes against expectations: warm sends 1 query per loop and never reconnects, while cold sends 2 per loop (SET NAMES + SELECT 1) and reconnects every time.
2. **27 instead of 30.** At `MaxConnectionsPercent=100`, `MaxDatabaseConnectionsAllowed` is 27 per node (54 total), not 30 (60 total). Why?
3. **Idle connections above the idle limit.** At `MaxIdleConnectionsPercent=50` (expected 15 per node), processlist showed 28 idle connections per proxy node. Why?
4. ✅ **SOLVED: Extra query per connection.** `QueryRequests` showed 2 queries per loop in storm.py, but the script runs only 1. What does pymysql (or the proxy) send on connect?

   - **Answer:** pymysql sends `SET NAMES utf8mb4` on every connect (seen with client/spy.py). 1408 loops × 2 queries = 2816, which matches CloudWatch `QueryRequests` Sum.
   - It doesn't pin: the proxy tracks character-set settings, and `SessionPinned` stayed 0 during the storms.
   - Possible link to Q1: each cold loop needs a DB connection twice (once for SET NAMES, once for SELECT 1).
   - Side lesson: `QueryRequests` had 4 datapoints that minute (min 1, max 1425). It isn't neatly one per node, so use **Sum** for totals.
