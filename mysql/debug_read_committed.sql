-- Debug READ COMMITTED not working as expected

-- Step 1: Check MySQL version and current settings
SELECT VERSION() as mysql_version;
SELECT @@transaction_isolation as current_isolation;
SELECT @@global.transaction_isolation as global_isolation;
SELECT @@autocommit as autocommit_status;

-- Step 2: Make sure we're starting fresh
-- If you have an open transaction, commit it first
-- COMMIT;

-- Step 3: Set isolation level BEFORE transaction
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Step 4: Verify it's set
SELECT @@transaction_isolation;
-- Should show: READ-COMMITTED

-- Step 5: Start transaction
START TRANSACTION;

-- Step 6: Check isolation level INSIDE transaction
SELECT @@transaction_isolation;
-- Should still show: READ-COMMITTED

-- Step 7: First read
SELECT balance FROM accounts WHERE id = 1;
-- Note this value

-- NOW: Have Terminal 2 update and commit
-- Then come back and do second read

-- Step 8: Second read (after Terminal 2 commits)
SELECT balance FROM accounts WHERE id = 1;
-- With READ COMMITTED, should see NEW value

COMMIT;

-- Alternative: Try using SET TRANSACTION (without SESSION)
-- This applies to the NEXT transaction only
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT balance FROM accounts WHERE id = 1;
-- Wait for Terminal 2...
SELECT balance FROM accounts WHERE id = 1;
COMMIT;

