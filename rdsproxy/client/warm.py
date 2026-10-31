"""Warm connection: each worker connects ONCE and reuses it for every request.

Same work as `storm.py ... app` (SELECT 1, then 200ms in the app),
but without connecting on every loop. This is what a client-side pool,
or a Lambda that connects outside its handler, does.

usage: python3 warm.py <host> <workers> [seconds]
"""
import sys, time, threading, collections, pymysql

HOST = sys.argv[1]
WORKERS = int(sys.argv[2])
SECONDS = int(sys.argv[3]) if len(sys.argv) > 3 else 10

ok = 0
errors = collections.Counter()
lock = threading.Lock()


def worker():
    global ok
    conn = pymysql.connect(host=HOST, user="admin", password="LabPassword123", autocommit=True)
    end = time.time() + SECONDS
    while time.time() < end:
        try:
            with conn.cursor() as c:
                c.execute("SELECT 1")   # ~1ms inside MySQL
            time.sleep(0.2)             # 200ms in the app, connection idle
            with lock:
                ok += 1
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

print(f"warm  workers={WORKERS}  ok={ok}  failed={sum(errors.values())}")
for msg, n in errors.most_common():
    print(f"  {n:6d} x {msg}")
