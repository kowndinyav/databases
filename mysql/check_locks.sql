-- ============================================
-- HOW TO CHECK WHY ROWS ARE LOCKED
-- ============================================

-- Method 1: Check all locks (MySQL 8.0+)
SELECT 
    lock_type,
    lock_mode,
    lock_status,
    lock_table,
    lock_index,
    lock_space,
    lock_page,
    lock_rec,
    lock_data,
    engine_lock_id,
    engine_transaction_id,
    thread_id,
    object_schema,
    object_name,
    index_name,
    lock_object_instance_begin
FROM performance_schema.data_locks
WHERE object_schema = 'testdb'
  AND object_name = 'accounts';

-- Method 2: Check lock waits (what's blocking what)
SELECT 
    requesting_engine_lock_id,
    requesting_engine_transaction_id,
    requesting_thread_id,
    blocking_engine_lock_id,
    blocking_engine_transaction_id,
    blocking_thread_id
FROM performance_schema.data_lock_waits;

-- Method 3: Combined view - see locks and what's waiting
SELECT 
    dl.lock_type,
    dl.lock_mode,
    dl.lock_status,
    dl.object_schema,
    dl.object_name,
    dl.index_name,
    dl.lock_data,
    dl.engine_transaction_id,
    p.id as process_id,
    p.user,
    p.host,
    p.db,
    p.command,
    p.time,
    p.state,
    p.info as query
FROM performance_schema.data_locks dl
LEFT JOIN information_schema.processlist p 
    ON p.id = dl.thread_id
WHERE dl.object_schema = 'testdb'
  AND dl.object_name = 'accounts';

-- Method 4: See what's blocking what (detailed)
SELECT 
    r.trx_id waiting_trx_id,
    r.trx_mysql_thread_id waiting_thread,
    r.trx_query waiting_query,
    r.trx_started waiting_started,
    TIMESTAMPDIFF(SECOND, r.trx_started, NOW()) as waiting_seconds,
    b.trx_id blocking_trx_id,
    b.trx_mysql_thread_id blocking_thread,
    b.trx_query blocking_query,
    b.trx_started blocking_started
FROM information_schema.innodb_lock_waits w
INNER JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id
INNER JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id;

-- Method 5: Check locks for specific row
SELECT 
    lock_type,
    lock_mode,
    lock_status,
    lock_data,
    engine_transaction_id
FROM performance_schema.data_locks
WHERE object_schema = 'testdb'
  AND object_name = 'accounts'
  AND lock_data LIKE '%id = 1%';  -- Adjust based on your row

-- Method 6: See all transactions with their locks
SELECT 
    t.trx_id,
    t.trx_state,
    t.trx_started,
    t.trx_mysql_thread_id,
    t.trx_query,
    t.trx_isolation_level,
    COUNT(DISTINCT l.lock_data) as locked_rows
FROM information_schema.innodb_trx t
LEFT JOIN performance_schema.data_locks l 
    ON l.engine_transaction_id = t.trx_id
WHERE l.object_schema = 'testdb'
  AND l.object_name = 'accounts'
GROUP BY t.trx_id, t.trx_state, t.trx_started, t.trx_mysql_thread_id, t.trx_query, t.trx_isolation_level;

