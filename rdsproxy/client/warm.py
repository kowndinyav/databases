"""Warm connection: each worker connects ONCE and reuses it for every request.

Same work as `storm.py ... app` (SELECT 1, then 200ms in the app),
but without connecting on every loop. This is what a client-side pool,
or a Lambda that connects outside its handler, does.

Prints p50/p99 of:
  connect : the one-time connect per worker
  query   : time for SELECT 1 to return (includes waiting for the proxy
            to lend a DB connection)

usage: python3 warm.py <host> <workers> [seconds]
"""
import sys, time, threading, collections, pymysql

HOST = sys.argv[1]
WORKERS = int(sys.argv[2])
SECONDS = int(sys.argv[3]) if len(sys.argv) > 3 else 10

ok = 0
errors = collections.Counter()
connect_ms = []
query_ms = []
lock = threading.Lock()


def worker():
    global ok
    t0 = time.perf_counter()
    conn = pymysql.connect(host=HOST, user="admin", password="LabPassword123", autocommit=True)
    with lock:
        connect_ms.append((time.perf_counter() - t0) * 1000)
    end = time.time() + SECONDS
    while time.time() < end:
        try:
            t0 = time.perf_counter()
            with conn.cursor() as c:
                c.execute("SELECT 1")   # ~1ms inside MySQL
            q = (time.perf_counter() - t0) * 1000
            with lock:
                ok += 1
                query_ms.append(q)
            time.sleep(0.2)             # 200ms in the app, connection idle
        except pymysql.err.MySQLError as e:
            with lock:
                errors[str(e)] += 1
            time.sleep(0.1)
    conn.close()


threads = [threading.Thread(target=worker) for _ in range(WORKERS)]
for t in threads:
    t.start()
for t in threads:
    t.join()


def pct(xs, q):
    xs = sorted(xs)
    return xs[int(q * (len(xs) - 1))]


print(f"warm  workers={WORKERS}  ok={ok}  failed={sum(errors.values())}")
if connect_ms:
    print(f"connect time ms: p50={pct(connect_ms, 0.5):.1f}  p99={pct(connect_ms, 0.99):.1f}  (once per worker)")
if query_ms:
    print(f"query time ms:   p50={pct(query_ms, 0.5):.1f}  p99={pct(query_ms, 0.99):.1f}  max={max(query_ms):.1f}")
for msg, n in errors.most_common():
    print(f"  {n:6d} x {msg}")
