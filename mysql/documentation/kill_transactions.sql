-- ============================================
-- HOW TO KILL TRANSACTIONS IN MYSQL
-- ============================================

-- Step 1: See all active transactions
SHOW PROCESSLIST;

-- Or more detailed view:
SELECT 
    ID,
    USER,
    HOST,
    DB,
    COMMAND,
    TIME,
    STATE,
    INFO
FROM information_schema.PROCESSLIST
WHERE COMMAND != 'Sleep';

-- Step 2: See transactions specifically
SELECT 
    trx_id,
    trx_state,
    trx_started,
    trx_mysql_thread_id,
    trx_query
FROM information_schema.innodb_trx;

-- Step 3: Kill a specific transaction/connection
-- Replace <thread_id> with the ID from SHOW PROCESSLIST
-- KILL <thread_id>;

-- Example:
-- KILL 123;

-- Step 4: Kill all your own transactions (be careful!)
-- This kills all connections for the current user
SELECT CONCAT('KILL ', id, ';') as kill_command
FROM information_schema.PROCESSLIST
WHERE USER = USER()
  AND id != CONNECTION_ID();

-- Step 5: Commit or rollback your current transaction
COMMIT;  -- or ROLLBACK;

-- Step 6: Check for locked transactions
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

