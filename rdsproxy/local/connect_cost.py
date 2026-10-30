"""P1: how expensive is opening a connection compared to running a query?

Runs N queries two ways:
  A) new connection per query  (what Lambda / PHP / short scripts do)
  B) one connection reused     (what a pool / RDS Proxy gives you)
"""
import sys, time, pymysql

N = int(sys.argv[1]) if len(sys.argv) > 1 else 200
CFG = dict(host="127.0.0.1", port=3307, user="root", password="root")

t0 = time.perf_counter()
for _ in range(N):
    conn = pymysql.connect(**CFG)
    with conn.cursor() as c:
        c.execute("SELECT 1")
    conn.close()
a = time.perf_counter() - t0

t0 = time.perf_counter()
conn = pymysql.connect(**CFG)
for _ in range(N):
    with conn.cursor() as c:
        c.execute("SELECT 1")
conn.close()
b = time.perf_counter() - t0

print(f"A) connect per query : {a*1000/N:6.2f} ms/query")
print(f"B) reused connection : {b*1000/N:6.2f} ms/query")
print(f"   connection overhead is ~{a/b:.0f}x the query itself")
