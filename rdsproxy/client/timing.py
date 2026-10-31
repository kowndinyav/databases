"""Time each step of one request, one client at a time (no concurrency, no queueing).

usage: python3 timing.py <host>
"""
import sys, time, pymysql

HOST = sys.argv[1]
N = 20

for i in range(N):
    t0 = time.perf_counter()
    conn = pymysql.connect(host=HOST, user="admin", password="LabPassword123", autocommit=True)
    t1 = time.perf_counter()
    with conn.cursor() as c:
        c.execute("SELECT 1")
    t2 = time.perf_counter()
    conn.close()
    t3 = time.perf_counter()
    print(f"connect={1000*(t1-t0):6.1f} ms   select1={1000*(t2-t1):6.1f} ms   close={1000*(t3-t2):5.1f} ms")
