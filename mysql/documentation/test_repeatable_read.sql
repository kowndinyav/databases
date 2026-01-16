-- ============================================
-- REPEATABLE READ ISOLATION LEVEL TEST SCRIPT
-- ============================================
-- This script demonstrates Repeatable Read isolation level behavior
-- Run these commands in separate MySQL client sessions to see the effects

-- ============================================
-- TEST 1: Consistent Reads Within a Transaction
-- ============================================
-- This demonstrates that within a transaction, reading the same row twice
-- will return the same value, even if another transaction modifies it.

-- SESSION 1 (Terminal 1):
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT * FROM accounts WHERE id = 1;
-- Note the balance value (e.g., 1000)

-- Now wait... (don't commit yet)
-- Go to SESSION 2 and update the balance
start transaction
UPDATE accounts SET balance = balance + 100 WHERE id = 1;
commit

-- Read again - should see the SAME value as before
SELECT * FROM accounts WHERE id = 1;
-- The balance should still be the original value, not the updated one

-- Commit to see the updated value
COMMIT;
SELECT * FROM accounts WHERE id = 1;
-- Now you'll see the updated value


-- SESSION 2 (Terminal 2):
-- While SESSION 1 is still in its transaction, run this:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

UPDATE accounts SET balance = balance + 100 WHERE id = 1;
SELECT * FROM accounts WHERE id = 1;
-- You'll see the updated value in this session

COMMIT;
-- After committing, SESSION 1 will still see the old value until it commits


-- ============================================
-- TEST 2: Non-Repeatable Read Prevention
-- ============================================
-- This shows that Repeatable Read prevents non-repeatable reads
-- (reading the same row twice and getting different values)

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT balance FROM accounts WHERE id = 1;
-- First read: e.g., 1000

-- Wait here...

SELECT balance FROM accounts WHERE id = 1;
-- Second read: Still 1000 (same as first read)
-- This is the "repeatable" part - same value repeated

COMMIT;


-- SESSION 2:
-- While SESSION 1 is reading, update the value
START TRANSACTION;
UPDATE accounts SET balance = 2000.00 WHERE id = 1;
COMMIT;

-- Even though SESSION 2 committed the change, SESSION 1 still sees the old value
-- until SESSION 1 commits or rolls back


-- ============================================
-- TEST 3: Phantom Reads (Still Possible in Repeatable Read)
-- ============================================
-- Repeatable Read prevents non-repeatable reads but NOT phantom reads
-- Phantom reads: new rows appearing in subsequent reads

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT COUNT(*) FROM accounts;
-- First count: e.g., 3

-- Wait here...

SELECT COUNT(*) FROM accounts;
-- Second count: Still 3 (consistent)
-- But if SESSION 2 inserts a new row...

SELECT * FROM accounts;
-- You might see a new row that wasn't there in the first SELECT
-- This is a phantom read (though MySQL's Repeatable Read uses Next-Key Locks
-- which can prevent some phantom reads)


-- SESSION 2:
-- Insert a new account while SESSION 1 is reading
START TRANSACTION;
INSERT INTO accounts (balance) VALUES (300);
COMMIT;

-- In MySQL with Repeatable Read, phantom reads are actually prevented
-- due to Next-Key Locking, so SESSION 1 won't see the new row


-- ============================================
-- TEST 4: Comparison with READ COMMITTED
-- ============================================
-- Compare Repeatable Read with Read Committed to see the difference

-- SESSION 1 (READ COMMITTED):
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

SELECT balance FROM accounts WHERE id = 1;
-- First read: 1000

-- Wait...

SELECT balance FROM accounts WHERE id = 1;
-- Second read: Might be different if SESSION 2 updated it!
-- This is a non-repeatable read (allowed in READ COMMITTED)

COMMIT;


-- SESSION 2:
START TRANSACTION;
UPDATE accounts SET balance = 1500.00 WHERE id = 1;
COMMIT;

-- In READ COMMITTED, SESSION 1's second read will see the updated value
-- In REPEATABLE READ, SESSION 1's second read will still see the old value


-- ============================================
-- TEST 5: Lock Behavior
-- ============================================
-- Repeatable Read uses shared locks that prevent updates until transaction ends

-- SESSION 1:
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
-- This acquires an exclusive lock
-- Don't commit yet...


-- SESSION 2:
-- Try to update the same row
START TRANSACTION;
UPDATE accounts SET balance = 9999.00 WHERE id = 1;
-- This will BLOCK/WAIT until SESSION 1 commits or rolls back
-- This demonstrates the locking mechanism


-- SESSION 1:
COMMIT;
-- Now SESSION 2's update will proceed


-- ============================================
-- HELPER QUERIES
-- ============================================

-- Check current isolation level
SELECT @@transaction_isolation;
SELECT @@tx_isolation;  -- For older MySQL versions

-- Check all accounts
SELECT * FROM accounts;

-- Reset test data (adjust IDs based on your actual data)
UPDATE accounts SET balance = 1000 WHERE id = 1;
UPDATE accounts SET balance = 500 WHERE id = 2;
UPDATE accounts SET balance = 750 WHERE id = 3;

