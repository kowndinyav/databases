-- Debug script to check isolation level behavior

-- First, let's verify what isolation level is actually active
SELECT @@transaction_isolation;
SELECT @@session.transaction_isolation;

-- Check the global default
SELECT @@global.transaction_isolation;

-- IMPORTANT: In MySQL, you need to set isolation level BEFORE starting the transaction
-- OR use SET TRANSACTION (without SESSION) which applies to the NEXT transaction only

-- Method 1: Set before transaction (CORRECT)
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT balance FROM accounts WHERE id = 1;

-- Method 2: Set for next transaction only
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT balance FROM accounts WHERE id = 1;

-- Method 3: Set inside transaction (WRONG - won't work!)
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;  -- Too late!
SELECT balance FROM accounts WHERE id = 1;

