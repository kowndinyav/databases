"""P2/P3: open connections one by one, keep them idle, until MySQL refuses.

Leave it running and look at the server from another terminal.
"""
import sys, pymysql

N = int(sys.argv[1]) if len(sys.argv) > 1 else 30
CFG = dict(host="127.0.0.1", port=3307, user="root", password="root")

held = []
for i in range(1, N + 1):
    try:
        held.append(pymysql.connect(**CFG))
        print(f"opened connection #{i}")
    except pymysql.err.OperationalError as e:
        print(f"connection #{i} FAILED: {e}")
        break

input(f"\nHolding {len(held)} idle connections. Press Enter to release...")
for c in held:
    c.close()
