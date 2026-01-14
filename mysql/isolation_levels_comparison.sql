-- ISOLATION LEVEL 1: READ UNCOMMITTED

-- SESSION 1:
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
START TRANSACTION;
SELECT balance FROM accounts WHERE id = 1;

-- SESSION 2:
START TRANSACTION;
UPDATE accounts SET balance = balance + 100 WHERE id = 1;

-- Don't commit yet
COMMIT;


-- SESSION 1:
ROLLBACK;  -- Oops, transaction failed
-- But SESSION 2 already saw the uncommitted value!


-- ============================================
-- ISOLATION LEVEL 2: READ COMMITTED
-- ============================================
-- Prevents dirty reads, but allows non-repeatable reads

-- SESSION 1:
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;

SELECT balance FROM accounts WHERE id = 1;
-- First read: 1000


-- SESSION 2:
START TRANSACTION;
UPDATE accounts SET balance = 2000 WHERE id = 1;
COMMIT;


-- SESSION 1:
SELECT balance FROM accounts WHERE id = 1;
-- Second read: 2000 (different from first read!)
-- This is a "non-repeatable read"

COMMIT;


-- ============================================
-- ISOLATION LEVEL 3: REPEATABLE READ (Default in MySQL)
-- ============================================
-- Prevents dirty reads and non-repeatable reads

-- SESSION 1:
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;

SELECT balance FROM accounts WHERE id = 1;
-- First read: 1000


-- SESSION 2:
START TRANSACTION;
UPDATE accounts SET balance = 2000 WHERE id = 1;
COMMIT;


-- SESSION 1:
SELECT balance FROM accounts WHERE id = 1;
-- Second read: Still 1000 (same as first read!)
-- Non-repeatable read prevented

COMMIT;
SELECT balance FROM accounts WHERE id = 1;
-- Now sees 2000


-- ============================================
-- ISOLATION LEVEL 4: SERIALIZABLE
-- ============================================
-- Highest isolation - prevents all anomalies

-- SESSION 1:
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
START TRANSACTION;

SELECT * FROM accounts WHERE balance > 500;
-- Creates shared locks on matching rows
-- Don't commit...


-- SESSION 2:
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
START TRANSACTION;

-- Even a simple SELECT might block!
SELECT * FROM accounts;
-- This might wait for SESSION 1 to commit
-- SERIALIZABLE is very strict

COMMIT;


-- SESSION 1:
COMMIT;


-- ============================================
-- COMPARISON TABLE TEST
-- ============================================

-- Test: Dirty Read
-- READ UNCOMMITTED: ✅ Allows
-- READ COMMITTED: ❌ Prevents
-- REPEATABLE READ: ❌ Prevents
-- SERIALIZABLE: ❌ Prevents

-- Test: Non-Repeatable Read
-- READ UNCOMMITTED: ✅ Allows
-- READ COMMITTED: ✅ Allows
-- REPEATABLE READ: ❌ Prevents
-- SERIALIZABLE: ❌ Prevents

-- Test: Phantom Read
-- READ UNCOMMITTED: ✅ Allows
-- READ COMMITTED: ✅ Allows
-- REPEATABLE READ: ❌ Prevents (MySQL uses gap locks)
-- SERIALIZABLE: ❌ Prevents

-- ============================================
-- CHECKING CURRENT ISOLATION LEVEL
-- ============================================

-- Check global default
SELECT @@global.transaction_isolation;

-- Check session level
SELECT @@session.transaction_isolation;
SELECT @@transaction_isolation;

-- Check for a specific connection
SHOW VARIABLES LIKE 'transaction_isolation';


-- ============================================
-- WHEN TO USE EACH LEVEL
-- ============================================

-- READ UNCOMMITTED:
-- - Reporting/analytics where slight inconsistency is OK
-- - Very high read performance needed
-- - Data accuracy not critical

-- READ COMMITTED:
-- - Most web applications
-- - When you want to see latest committed data
-- - Good balance of performance and safety

-- REPEATABLE READ (MySQL default):
-- - Financial transactions
-- - When you need consistent snapshots
-- - Multi-step validations
-- - Report generation

-- SERIALIZABLE:
-- - Critical financial systems
-- - When absolute consistency is required
-- - When you can tolerate more blocking

