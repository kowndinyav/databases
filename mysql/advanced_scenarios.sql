-- ============================================
-- ADVANCED REPEATABLE READ SCENARIOS
-- ============================================

-- ============================================
-- TEST 6: Deadlock Scenario
-- ============================================
-- Two transactions waiting on each other's locks

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
-- Lock acquired on id=1
-- Wait here...

SELECT * FROM accounts WHERE id = 2 FOR UPDATE;
-- This will try to lock id=2, but SESSION 2 might have it


-- SESSION 2:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT * FROM accounts WHERE id = 2 FOR UPDATE;
-- Lock acquired on id=2

SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
-- This will BLOCK waiting for SESSION 1's lock on id=1
-- If SESSION 1 now tries to lock id=2, you'll get a DEADLOCK!

-- MySQL will detect the deadlock and rollback one transaction
-- Check: SHOW ENGINE INNODB STATUS; to see deadlock info


-- ============================================
-- TEST 7: Gap Locks (MySQL Specific)
-- ============================================
-- MySQL uses gap locks to prevent phantom reads in Repeatable Read

-- First, let's see what IDs exist
SELECT id FROM accounts ORDER BY id;

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- This creates a gap lock on the range
SELECT * FROM accounts WHERE id BETWEEN 5 AND 10 FOR UPDATE;
-- Even if no rows exist in this range, a gap lock is created
-- Don't commit yet...


-- SESSION 2:
-- Try to insert a row in the gap
START TRANSACTION;
INSERT INTO accounts (balance) VALUES (500);
-- If the auto-increment ID falls in the gap (5-10), this will BLOCK!
-- This is how MySQL prevents phantom reads

-- Check what's happening:
SHOW ENGINE INNODB STATUS\G
-- Look for "LOCK WAIT" and gap lock information


-- SESSION 1:
COMMIT;
-- Now SESSION 2 can proceed


-- ============================================
-- TEST 8: Next-Key Locks
-- ============================================
-- Combination of record lock + gap lock

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- This creates a next-key lock
SELECT * FROM accounts WHERE id > 2 FOR UPDATE;
-- Locks id=3, id=4, etc. AND the gap after them
-- Don't commit...


-- SESSION 2:
-- Try to insert or update in the locked range
START TRANSACTION;
INSERT INTO accounts (balance) VALUES (600);
-- Will block if ID falls in locked range

UPDATE accounts SET balance = 999 WHERE id = 3;
-- Will block if id=3 exists


-- SESSION 1:
COMMIT;


-- ============================================
-- TEST 9: Range Queries and Consistency
-- ============================================
-- Testing how range queries maintain consistency

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT SUM(balance) FROM accounts WHERE id BETWEEN 1 AND 5;
-- First sum: e.g., 2250
-- Don't commit...


-- SESSION 2:
START TRANSACTION;
UPDATE accounts SET balance = balance + 100 WHERE id = 1;
INSERT INTO accounts (balance) VALUES (400);
COMMIT;


-- SESSION 1:
SELECT SUM(balance) FROM accounts WHERE id BETWEEN 1 AND 5;
-- Still 2250! (or original value)
-- The new row and updated balance are not visible

COMMIT;
SELECT SUM(balance) FROM accounts WHERE id BETWEEN 1 AND 5;
-- Now includes the changes


-- ============================================
-- TEST 10: Write Skew Problem
-- ============================================
-- A subtle concurrency issue that Repeatable Read doesn't prevent

-- Setup: Add a constraint check
-- Assume: Total balance should never exceed 5000

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT SUM(balance) FROM accounts;
-- Total: e.g., 2000 (well below 5000 limit)
-- Decision: I can safely add 2000

-- Wait here...

INSERT INTO accounts (balance) VALUES (2000);
-- This might violate the constraint if SESSION 2 also adds!


-- SESSION 2:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT SUM(balance) FROM accounts;
-- Also sees 2000 (from snapshot)
-- Decision: I can also safely add 2000

INSERT INTO accounts (balance) VALUES (2000);
COMMIT;
-- Total is now 4000, still OK


-- SESSION 1:
COMMIT;
-- Total is now 6000! Constraint violated!
-- This is "write skew" - Repeatable Read doesn't prevent this
-- Solution: Use SERIALIZABLE or application-level locking


-- ============================================
-- TEST 11: Lost Update Problem
-- ============================================
-- Testing if Repeatable Read prevents lost updates

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT balance FROM accounts WHERE id = 1;
-- Read: 1000
-- Calculate new balance: 1000 + 100 = 1100
-- Don't update yet...


-- SESSION 2:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT balance FROM accounts WHERE id = 1;
-- Also reads: 1000
UPDATE accounts SET balance = balance + 50 WHERE id = 1;
COMMIT;
-- Balance is now 1050


-- SESSION 1:
UPDATE accounts SET balance = 1100 WHERE id = 1;
-- This OVERWRITES SESSION 2's update!
COMMIT;
-- Balance is 1100, but should be 1150 (1000 + 100 + 50)
-- This is a "lost update" - Repeatable Read doesn't prevent this!

-- Solution: Use SELECT ... FOR UPDATE or optimistic locking


-- ============================================
-- TEST 12: Correct Way to Prevent Lost Updates
-- ============================================

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT balance FROM accounts WHERE id = 1 FOR UPDATE;
-- Lock acquired, prevents other transactions from updating
-- Read: 1000


-- SESSION 2:
START TRANSACTION;
SELECT balance FROM accounts WHERE id = 1 FOR UPDATE;
-- This will BLOCK until SESSION 1 commits


-- SESSION 1:
UPDATE accounts SET balance = balance + 100 WHERE id = 1;
COMMIT;
-- Balance updated to 1100


-- SESSION 2:
-- Now proceeds, reads 1100
UPDATE accounts SET balance = balance + 50 WHERE id = 1;
COMMIT;
-- Balance is now 1150 - correct!

