# Parked questions (revisit later)

1. **Tiny-pool throughput.** With only 2 DB connections (5% pool), 100 app-idle workers got just ~35–60 requests/s, both cold (recap-01 #11) and warm (#14). MySQL answers `SELECT 1` in ~1 ms (`QueryDatabaseResponseLatency`), so where do the other ~30–50 ms per request go inside the proxy?
   - Idea to check: proxy debug logs, and whether moving a DB connection from one client to another costs time.
2. **27 instead of 30.** At `MaxConnectionsPercent=100`, `MaxDatabaseConnectionsAllowed` is 27 per node (54 total), not 30 (60 total). Why?
3. **Idle connections above the idle limit.** At `MaxIdleConnectionsPercent=50` (expected 15 per node), processlist showed 28 idle connections per proxy node. Why?
4. **Extra query per connection.** `QueryRequests` showed 2 queries per loop in storm.py, but the script runs only 1. What does pymysql (or the proxy) send on connect?
