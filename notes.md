When start transaction and update
- always involves 2 locks: Intent lock, Row lock

Intent Lock is about protecting from DDL change from a different transaction
- Why is Record level lock not sufficient?
    - It is sufficient but not efficient i.e, if there are 10000 rows locked in transaction, we created one intent lock for table and 10000 record locks. Scanning through all record level locks vs one table level lock, table level locking is more efficient

Gap locks
- meant for preventing phantom reads in repeatable read and serializable isolation levels. other isolation levels, phantom reads are allowed

Phantom Read Definition:
Phantom Read = Number of rows changes (increase OR decrease)

Example
```
-- Transaction 1
SELECT COUNT(*) FROM accounts WHERE balance > 1000;  -- 3 rows

-- Another transaction INSERTs a row
SELECT COUNT(*) FROM accounts WHERE balance > 1000;  -- 4 rows ✅ Phantom!
```



Query	                READ UNCOMMITTED	READ COMMITTED	REPEATABLE-READ	    SERIALIZABLE
SELECT ...	            No locks	        No locks	    No locks	        S locks
SELECT ... FOR UPDATE	X locks	            X locks	        X locks + gaps	    X locks + gaps
SELECT ... FOR SHARE	S locks	            S locks	        S locks + gaps	    S locks + gaps
UPDATE/DELETE	        X locks	            X locks	        X locks + gaps	    X locks + gaps


For lost updates problem, regardless of the isolation level, you need explicit locking

MVCC helps in preventing phantom reads for - NonLock READS

"Gap Locks" help in preventing phantom reads for - Lock READS



Metadata Locks (MDL):
✅ Protect table structure
✅ Created automatically on any table access
✅ Prevent DDL while transactions are using the table
✅ Released on COMMIT/ROLLBACK
❌ Not about data conflicts (that's data locks)


start transaction;
SELECT * FROM accounts WHERE id BETWEEN 5 AND 10;

insert into accounts (id, balance, email) values (9, 3280, "caa@bb.com");