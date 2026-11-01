"""Print every command pymysql sends during one storm loop: connect -> SELECT 1 -> close.

usage: python3 spy.py <host>
"""
import sys, pymysql, pymysql.connections as pc

orig = pc.Connection._execute_command


def spy(self, command, sql):
    print("SENT:", command, sql)  # command 3 = query, 1 = quit
    return orig(self, command, sql)


pc.Connection._execute_command = spy

conn = pymysql.connect(host=sys.argv[1], user="admin", password="LabPassword123", autocommit=True)
conn.cursor().execute("SELECT 1")
conn.close()
