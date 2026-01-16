-- Verify what's actually happening with isolation levels

-- Check MySQL version
SELECT VERSION();

-- Check current isolation level settings
SELECT @@transaction_isolation;
SELECT @@session.transaction_isolation;
SELECT @@global.transaction_isolation;

-- Check if autocommit is on
SELECT @@autocommit;

-- IMPORTANT: In MySQL, you might need to explicitly verify
-- Let's test READ COMMITTED properly

-- Step 1: Make sure we're starting fresh
COMMIT;  -- End any existing transaction
SET autocommit = 1;  -- Turn on autocommit

-- Step 2: Set isolation level
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Step 3: Verify it's set
SELECT @@transaction_isolation;
-- Should show: READ-COMMITTED

-- Step 4: Now start transaction
START TRANSACTION;

-- Step 5: Verify isolation level is still what we set
SELECT @@transaction_isolation;
-- This should still show READ-COMMITTED

-- Step 6: Read the balance
SELECT balance FROM accounts WHERE id = 1;

-- Now wait for Terminal 2 to update and commit...

-- Step 7: Read again
SELECT balance FROM accounts WHERE id = 1;
-- With READ COMMITTED, this should see the NEW value

COMMIT;

