-- ============================================
-- CONCRETE EXAMPLE: How IX Locks Help
-- ============================================

-- SCENARIO 1: Preventing DDL conflicts while DML is running
-- ============================================

-- Terminal 1: Start a transaction that modifies rows
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

UPDATE accounts SET balance = balance + 100 WHERE id = 1;
-- This creates:
-- 1. IX lock on TABLE (accounts)
-- 2. X lock on row id=1
-- Don't commit yet!


-- Terminal 2: Try to do DDL (ALTER TABLE) while Terminal 1 has IX lock
-- This will BLOCK because of the IX lock!
ALTER TABLE accounts ADD COLUMN last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
-- This will WAIT because Terminal 1 has an IX lock
-- MySQL knows there's an active transaction modifying the table


-- Terminal 1: Commit releases the IX lock
COMMIT;
-- Now Terminal 2's ALTER TABLE can proceed


-- ============================================
-- SCENARIO 2: Deadlock Detection
-- ============================================

-- Terminal 1:
START TRANSACTION;
UPDATE accounts SET balance = balance + 100 WHERE id = 1;
-- Creates IX lock on TABLE + X lock on row 1
-- Don't commit...


-- Terminal 2:
START TRANSACTION;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
-- Creates IX lock on TABLE + X lock on row 2
-- Don't commit...


-- Terminal 1: Try to update row 2
UPDATE accounts SET balance = balance + 50 WHERE id = 2;
-- This will BLOCK waiting for Terminal 2's lock on row 2


-- Terminal 2: Try to update row 1
UPDATE accounts SET balance = balance + 50 WHERE id = 1;
-- This creates a DEADLOCK!
-- MySQL detects it because:
-- 1. Both have IX locks (table-level intent)
-- 2. Both are waiting for each other's row locks
-- MySQL will automatically rollback one transaction


-- ============================================
-- SCENARIO 3: Multiple Transactions Modifying Different Rows
-- ============================================

-- Terminal 1:
START TRANSACTION;
UPDATE accounts SET balance = balance + 100 WHERE id = 1;
-- IX lock on TABLE, X lock on row 1


-- Terminal 2:
START TRANSACTION;
UPDATE accounts SET balance = balance + 200 WHERE id = 2;
-- IX lock on TABLE, X lock on row 2
-- Both can proceed because:
-- - Both have IX locks (compatible - both are "intent")
-- - They're locking different rows (id=1 vs id=2)
-- The IX locks don't block each other!

COMMIT;  -- Terminal 1
COMMIT;  -- Terminal 2


-- ============================================
-- SCENARIO 4: What happens WITHOUT IX locks (conceptual)
-- ============================================
-- If MySQL didn't have IX locks:

-- Terminal 1: UPDATE row 1
-- Terminal 2: ALTER TABLE (add column)
-- Without IX locks, MySQL wouldn't know Terminal 1 is modifying the table
-- Terminal 2's ALTER TABLE might proceed, causing:
-- - Data corruption
-- - Inconsistent state
-- - Lost updates

-- With IX locks:
-- Terminal 1: UPDATE row 1 → Creates IX lock
-- Terminal 2: ALTER TABLE → Sees IX lock, knows table is being modified, WAITS
-- This prevents conflicts!


-- ============================================
-- TEST: See IX locks in action
-- ============================================

-- Terminal 1:
START TRANSACTION;
UPDATE accounts SET balance = balance + 100 WHERE id = 1;

-- Check locks:
SELECT 
    lock_type,
    lock_mode,
    lock_status,
    lock_data,
    object_name
FROM performance_schema.data_locks
WHERE object_schema = 'testdb'
  AND object_name = 'accounts';
-- You'll see both TABLE (IX) and RECORD (X) locks

-- Don't commit yet...


-- Terminal 2: Try DDL
ALTER TABLE accounts ADD COLUMN test_col INT;
-- This will BLOCK because Terminal 1 has IX lock
-- Check: SHOW PROCESSLIST; to see it waiting

-- Terminal 1:
COMMIT;
-- Now Terminal 2's ALTER TABLE proceeds

