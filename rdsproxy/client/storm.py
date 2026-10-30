"""Connection storm, in two modes.

WORKERS threads run for SECONDS. Each loop: connect -> work -> disconnect.

  db  : the 200ms is spent INSIDE MySQL (SELECT SLEEP(0.2)).
        Connection is busy the whole time. DB is the choke point;
        a proxy can't shrink the number of DB connections needed.

  app : MySQL work is tiny (SELECT 1), then the app spends 200ms
        doing "other work" (time.sleep) while still holding the connection.
        Connection is mostly idle. This is where a proxy multiplexes.

usage: python3 storm.py <host> <workers> <db|app> [seconds]
"""
import sys, time, threading, collections, pymysql

HOST = sys.argv[1]
WORKERS = int(sys.argv[2])
MODE = sys.argv[3]
SECONDS = int(sys.argv[4]) if len(sys.argv) > 4 else 10

ok = 0
errors = collections.Counter()
connect_ms = []
lock = threading.Lock()


def work(conn):
    with conn.cursor() as c:
        if MODE == "db":
            c.execute("SELECT SLEEP(0.2)")  # 200ms busy inside MySQL
        else:
            c.execute("SELECT 1")           # ~1ms inside MySQL
            time.sleep(0.2)                 # 200ms in the app, connection idle


def worker():
    global ok
    end = time.time() + SECONDS
    while time.time() < end:
        try:
            t0 = time.perf_counter()
            # autocommit=True: no transaction is left open after each query,
            # so a proxy is free to lend the DB connection to someone else.
            conn = pymysql.connect(host=HOST, user="admin", password="LabPassword123", autocommit=True)
            t1 = time.perf_counter()
            work(conn)
            conn.close()
            with lock:
                ok += 1
                connect_ms.append((t1 - t0) * 1000)
        except pymysql.err.MySQLError as e:
            with lock:
                errors[str(e)] += 1
            time.sleep(0.1)


threads = [threading.Thread(target=worker) for _ in range(WORKERS)]
for t in threads:
    t.start()
for t in threads:
    t.join()

connect_ms.sort()
print(f"mode={MODE}  workers={WORKERS}  ok={ok}  failed={sum(errors.values())}")
if connect_ms:
    p = lambda q: connect_ms[int(q * (len(connect_ms) - 1))]
    print(f"connect time ms: p50={p(0.5):.1f}  p99={p(0.99):.1f}")
for msg, n in errors.most_common():
    print(f"  {n:6d} x {msg}")
