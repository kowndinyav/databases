SHOW PROCESSLIST;


# show open transactions
SELECT * FROM information_schema.innodb_trx;

-- Find the ID from SHOW PROCESSLIST, then:
KILL <thread_id>;

-- First, see what you'll kill:
SELECT CONCAT('KILL ', id, ';') as kill_command
FROM information_schema.PROCESSLIST
WHERE USER = USER()
  AND id != CONNECTION_ID();


# check locks on a table

SELECT 
    lock_type,
    lock_mode,
    lock_status,
    lock_data,
    engine_transaction_id,
    thread_id
FROM performance_schema.data_locks
WHERE object_schema = 'testdb'
  AND object_name = 'accounts';


-- Check what's blocking what (MySQL 8.0+)
SELECT 
    r.trx_id waiting_trx_id,
    r.trx_mysql_thread_id waiting_thread,
    r.trx_query waiting_query,
    b.trx_id blocking_trx_id,
    b.trx_mysql_thread_id blocking_thread,
    b.trx_query blocking_query
FROM performance_schema.data_lock_waits w
INNER JOIN information_schema.innodb_trx b 
    ON b.trx_id = w.blocking_engine_transaction_id
INNER JOIN information_schema.innodb_trx r 
    ON r.trx_id = w.requesting_engine_transaction_id;

