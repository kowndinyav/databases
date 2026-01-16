-- ============================================
-- MYSQL/INNODB SPECIFIC BEHAVIOR
-- ============================================

-- ============================================
-- MVCC (Multi-Version Concurrency Control)
-- ============================================
-- InnoDB uses MVCC to implement isolation levels

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT * FROM accounts WHERE id = 1;
-- InnoDB creates a read view at transaction start
-- This read view is used for all subsequent reads


-- SESSION 2:
START TRANSACTION;
UPDATE accounts SET balance = 5000 WHERE id = 1;
COMMIT;
-- Creates a new version of the row


-- SESSION 1:
SELECT * FROM accounts WHERE id = 1;
-- Still sees the old version (from its read view)
-- InnoDB maintains multiple versions of rows

COMMIT;
-- Read view is released


-- ============================================
-- Next-Key Locking
-- ============================================
-- MySQL's way of preventing phantom reads

-- Check lock information
SHOW ENGINE INNODB STATUS\G
-- Look for "TRANSACTIONS" section

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- This creates a next-key lock
SELECT * FROM accounts WHERE id BETWEEN 3 AND 7 FOR UPDATE;
-- Locks:
-- 1. Record locks on existing rows (id=3, 4, 5, 6, 7)
-- 2. Gap locks on ranges between records
-- 3. Gap lock after the last record


-- SESSION 2:
START TRANSACTION;

-- These will BLOCK:
INSERT INTO accounts (balance) VALUES (100);  -- If ID falls in gap
UPDATE accounts SET balance = 999 WHERE id = 3;  -- Record lock
UPDATE accounts SET balance = 999 WHERE id = 8;  -- Gap lock after range

-- Check what's blocking:
SELECT * FROM performance_schema.data_locks;
SELECT * FROM performance_schema.data_lock_waits;


-- SESSION 1:
COMMIT;


-- ============================================
-- Gap Locks
-- ============================================

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Even selecting non-existent rows creates gap locks
SELECT * FROM accounts WHERE id = 99 FOR UPDATE;
-- Creates a gap lock preventing inserts of id=99


-- SESSION 2:
START TRANSACTION;
INSERT INTO accounts (id, balance) VALUES (99, 100);
-- BLOCKS! Gap lock prevents this insert


-- SESSION 1:
COMMIT;


-- ============================================
-- Record Locks vs Gap Locks vs Next-Key Locks
-- ============================================

-- Record Lock: Locks only the specific row
-- Gap Lock: Locks the gap between rows
-- Next-Key Lock: Record lock + Gap lock (combination)

-- View current locks
SELECT 
    lock_type,
    lock_mode,
    lock_status,
    lock_data
FROM performance_schema.data_locks
WHERE object_schema = 'testdb'
  AND object_name = 'accounts';


-- ============================================
-- Consistent Read vs Locking Read
-- ============================================

-- Consistent Read (default SELECT)
-- Uses MVCC, reads from snapshot, no locks
SELECT * FROM accounts WHERE id = 1;
-- Non-blocking, reads from read view


-- Locking Read (SELECT ... FOR UPDATE or SELECT ... LOCK IN SHARE MODE)
-- Acquires locks, reads latest committed version
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
-- Blocks other transactions, reads current committed data


-- ============================================
-- Read View Snapshot
-- ============================================

-- Each transaction gets a read view at START TRANSACTION
-- This view determines which row versions are visible

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- Read view created here

SELECT * FROM accounts;
-- Uses read view from transaction start


-- SESSION 2:
START TRANSACTION;
UPDATE accounts SET balance = 9999 WHERE id = 1;
COMMIT;
-- Creates new row version


-- SESSION 1:
SELECT * FROM accounts WHERE id = 1;
-- Still sees old version (from its read view)

COMMIT;
-- Read view released


-- ============================================
-- Undo Logs
-- ============================================
-- InnoDB uses undo logs to maintain row versions

-- Check undo log information
SHOW VARIABLES LIKE 'innodb_undo%';

-- Undo logs store:
-- - Previous versions of modified rows
-- - Used for rollback
-- - Used for consistent reads in other transactions


-- ============================================
-- Lock Timeout
-- ============================================

-- Set lock wait timeout
SET innodb_lock_wait_timeout = 50;  -- seconds

-- If a lock wait exceeds this, you'll get:
-- ERROR 1205 (HY000): Lock wait timeout exceeded; try restarting transaction


-- ============================================
-- Deadlock Detection
-- ============================================

-- MySQL automatically detects deadlocks
-- One transaction is rolled back

-- Check deadlock information
SHOW ENGINE INNODB STATUS\G
-- Look for "LATEST DETECTED DEADLOCK" section

-- Or query:
SELECT * FROM performance_schema.events_statements_history
WHERE sql_text LIKE '%deadlock%';


-- ============================================
-- Transaction Isolation vs Locking
-- ============================================

-- Isolation Level: Controls what you SEE (read consistency)
-- Locking: Controls what you can DO (write conflicts)

-- REPEATABLE READ:
-- - Read consistency: See same snapshot
-- - Locking: Uses shared locks for reads, exclusive for writes
-- - Gap locks prevent phantom reads


-- ============================================
-- Monitoring Locks
-- ============================================

-- Show all locks
SELECT * FROM performance_schema.data_locks;

-- Show lock waits
SELECT * FROM performance_schema.data_lock_waits;

-- Show blocking queries
SELECT 
    r.trx_id waiting_trx_id,
    r.trx_mysql_thread_id waiting_thread,
    r.trx_query waiting_query,
    b.trx_id blocking_trx_id,
    b.trx_mysql_thread_id blocking_thread,
    b.trx_query blocking_query
FROM information_schema.innodb_lock_waits w
INNER JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id
INNER JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id;


-- ============================================
-- Tips for Repeatable Read
-- ============================================

-- 1. Keep transactions short to reduce lock duration
-- 2. Use SELECT ... FOR UPDATE when you need to update based on current value
-- 3. Be aware of gap locks - they can block inserts
-- 4. Monitor for deadlocks and adjust application logic
-- 5. Use appropriate indexes to minimize lock ranges

