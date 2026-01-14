-- ============================================
-- REAL-WORLD SCENARIOS WITH REPEATABLE READ
-- ============================================

-- ============================================
-- SCENARIO 1: Bank Account Transfer
-- ============================================
-- Transferring money between accounts

-- SESSION 1: Transfer $100 from account 1 to account 2
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Check both balances
SELECT balance FROM accounts WHERE id = 1;
SELECT balance FROM accounts WHERE id = 2;

-- Verify sufficient funds (in real app, check balance > 100)
-- Deduct from source
UPDATE accounts SET balance = balance - 100 WHERE id = 1;

-- Wait here (simulating processing time)...

-- Add to destination
UPDATE accounts SET balance = balance + 100 WHERE id = 2;

-- Verify final balances
SELECT balance FROM accounts WHERE id = 1;
SELECT balance FROM accounts WHERE id = 2;

COMMIT;


-- SESSION 2: Another transfer happening concurrently
-- While SESSION 1 is processing, try to read balances
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT balance FROM accounts WHERE id = 1;
SELECT balance FROM accounts WHERE id = 2;
-- Sees old balances until SESSION 1 commits

COMMIT;


-- ============================================
-- SCENARIO 2: Financial Report Generation
-- ============================================
-- Generating a report that needs consistent data

-- SESSION 1: Generate end-of-day report
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Get all account balances
SELECT id, balance FROM accounts ORDER BY id;

-- Calculate totals
SELECT 
    COUNT(*) as account_count,
    SUM(balance) as total_balance,
    AVG(balance) as avg_balance,
    MIN(balance) as min_balance,
    MAX(balance) as max_balance
FROM accounts;

-- All these queries see the same snapshot
-- Even if SESSION 2 updates accounts, this report stays consistent

COMMIT;


-- SESSION 2: Customer making a deposit
START TRANSACTION;
UPDATE accounts SET balance = balance + 500 WHERE id = 1;
COMMIT;
-- This update won't affect SESSION 1's report


-- ============================================
-- SCENARIO 3: Inventory Check and Update
-- ============================================
-- Checking inventory before updating

-- Setup: Add inventory table
CREATE TABLE IF NOT EXISTS inventory (
    id INT PRIMARY KEY,
    product_name VARCHAR(100),
    quantity INT
);

INSERT INTO inventory VALUES 
    (1, 'Widget A', 10),
    (2, 'Widget B', 5);

-- SESSION 1: Check and reserve inventory
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT quantity FROM inventory WHERE id = 1;
-- Check if quantity >= 3
-- If yes, reserve 3 units

UPDATE inventory SET quantity = quantity - 3 WHERE id = 1;
-- Don't commit yet...


-- SESSION 2: Another order for the same product
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT quantity FROM inventory WHERE id = 1;
-- Sees old quantity (before SESSION 1's update)
-- Might also try to reserve 3 units

UPDATE inventory SET quantity = quantity - 3 WHERE id = 1;
-- This could cause negative inventory!

COMMIT;


-- SESSION 1:
COMMIT;
-- Now check: SELECT quantity FROM inventory WHERE id = 1;
-- Might be negative or incorrect!

-- Solution: Use SELECT ... FOR UPDATE to lock the row


-- ============================================
-- SCENARIO 4: Audit Trail with Consistent Reads
-- ============================================
-- Reading historical state for auditing

-- SESSION 1: Audit query - needs consistent view
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Read account state at transaction start
SELECT id, balance, 
       CASE 
           WHEN balance < 0 THEN 'OVERDRAWN'
           WHEN balance < 100 THEN 'LOW'
           ELSE 'OK'
       END as status
FROM accounts;

-- Generate audit report based on this snapshot
-- Even if accounts are updated, audit stays consistent

COMMIT;


-- SESSION 2: Regular account updates
START TRANSACTION;
UPDATE accounts SET balance = balance - 200 WHERE id = 1;
COMMIT;
-- Doesn't affect audit report


-- ============================================
-- SCENARIO 5: Batch Processing
-- ============================================
-- Processing multiple accounts in a batch

-- SESSION 1: Batch update job
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Process all accounts with balance < 100
SELECT id, balance FROM accounts WHERE balance < 100;
-- Gets consistent list

-- Apply interest or fee to each
UPDATE accounts SET balance = balance + 5 WHERE balance < 100;
-- All updates based on the same snapshot

COMMIT;


-- SESSION 2: Customer transaction
START TRANSACTION;
UPDATE accounts SET balance = balance + 50 WHERE id = 2;
COMMIT;
-- If balance was 80, it becomes 130
-- But SESSION 1's batch job might have already read it as < 100
-- This is why consistent snapshots matter for batch jobs


-- ============================================
-- SCENARIO 6: Multi-Step Validation
-- ============================================
-- Validating multiple conditions before action

-- SESSION 1: Complex validation
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Step 1: Check account 1 balance
SELECT balance FROM accounts WHERE id = 1;

-- Step 2: Check account 2 balance  
SELECT balance FROM accounts WHERE id = 2;

-- Step 3: Check total
SELECT SUM(balance) as total FROM accounts WHERE id IN (1, 2);

-- All three reads see the same snapshot
-- Can make decision based on consistent data

-- If conditions met, perform action
-- UPDATE accounts SET balance = ... WHERE ...

COMMIT;


-- SESSION 2: Concurrent updates
START TRANSACTION;
UPDATE accounts SET balance = balance + 100 WHERE id = 1;
COMMIT;
-- Won't affect SESSION 1's validation logic

