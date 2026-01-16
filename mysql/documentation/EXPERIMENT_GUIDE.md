# Repeatable Read Isolation Level - Experiment Guide

## What is Repeatable Read?

**Repeatable Read** ensures that:
- Within a transaction, if you read the same row multiple times, you'll **always get the same value**
- Other transactions cannot modify rows you've read until your transaction completes
- Prevents **non-repeatable reads** (reading the same row twice and getting different values)

## Quick Setup

1. Connect to your MySQL container:
```bash
docker exec -it mysql-lab mysql -uroot -proot testdb
```

2. Open **TWO terminal windows** - you'll need both to run concurrent transactions

## Experiment 1: The "Repeatable" Part (Core Concept)

### Terminal 1 (Session 1):
```sql
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT * FROM accounts WHERE id = 1;
-- Note the balance value
```

### Terminal 2 (Session 2):
```sql
-- While Session 1 is still running, update the balance
START TRANSACTION;
UPDATE accounts SET balance = balance + 500 WHERE id = 1;
COMMIT;
SELECT * FROM accounts WHERE id = 1;  -- You'll see the new value
```

### Back to Terminal 1:
```sql
-- Read the same row again (Session 2 already committed)
SELECT * FROM accounts WHERE id = 1;
-- You'll still see the OLD value! This is "repeatable read"

COMMIT;
SELECT * FROM accounts WHERE id = 1;
-- NOW you'll see the updated value
```

**Key Takeaway**: Within a transaction, reads are consistent - you see a snapshot from when the transaction started.

## Experiment 2: Compare with READ COMMITTED

### Terminal 1 (READ COMMITTED):
```sql
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

SELECT balance FROM accounts WHERE id = 1;
-- First read: e.g., 1000
```

### Terminal 2:
```sql
UPDATE accounts SET balance = 2000 WHERE id = 1;
COMMIT;
```

### Back to Terminal 1:
```sql
SELECT balance FROM accounts WHERE id = 1;
-- Second read: NOW shows 2000 (different from first read!)
-- This is a "non-repeatable read" - allowed in READ COMMITTED

COMMIT;
```

**Key Difference**: 
- **READ COMMITTED**: Each read sees the latest committed data
- **REPEATABLE READ**: All reads within a transaction see the same snapshot

## Experiment 3: Locking Behavior

### Terminal 1:
```sql
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
-- Acquires an exclusive lock - don't commit yet!
```

### Terminal 2:
```sql
-- Try to update the same row
UPDATE accounts SET balance = 9999 WHERE id = 1;
-- This will BLOCK/WAIT (you'll see it hanging)
```

### Back to Terminal 1:
```sql
COMMIT;
-- Now Terminal 2's update will proceed
```

**Key Takeaway**: `FOR UPDATE` creates exclusive locks that block other transactions.

## Experiment 4: Phantom Reads (Advanced)

MySQL's Repeatable Read actually prevents phantom reads using Next-Key Locks:

### Terminal 1:
```sql
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT COUNT(*) FROM accounts;
-- First count: e.g., 3
```

### Terminal 2:
```sql
INSERT INTO accounts (balance) VALUES (300);
COMMIT;
```

### Back to Terminal 1:
```sql
SELECT COUNT(*) FROM accounts;
-- Still 3! Phantom read prevented
SELECT * FROM accounts;
-- Still same rows - new row not visible

COMMIT;
SELECT * FROM accounts;
-- NOW you'll see the new row
```

## Helper Queries

```sql
-- Check current isolation level
SELECT @@transaction_isolation;

-- View all accounts
SELECT * FROM accounts;

-- Check for blocking queries
SHOW PROCESSLIST;
```

## Additional Test Files

I've created comprehensive test scripts for deeper exploration:

1. **`test_repeatable_read.sql`** - Basic tests (Tests 1-5)
2. **`advanced_scenarios.sql`** - Advanced topics:
   - Deadlocks (Test 6)
   - Gap Locks (Test 7)
   - Next-Key Locks (Test 8)
   - Range Queries (Test 9)
   - Write Skew Problem (Test 10)
   - Lost Update Problem (Test 11-12)

3. **`real_world_examples.sql`** - Practical scenarios:
   - Bank account transfers
   - Financial report generation
   - Inventory management
   - Audit trails
   - Batch processing

4. **`isolation_levels_comparison.sql`** - Compare all 4 isolation levels:
   - READ UNCOMMITTED
   - READ COMMITTED
   - REPEATABLE READ
   - SERIALIZABLE

5. **`mysql_specific_behavior.sql`** - MySQL/InnoDB specifics:
   - MVCC (Multi-Version Concurrency Control)
   - Next-Key Locking
   - Gap Locks
   - Undo Logs
   - Lock monitoring

## Summary

| Isolation Level | Non-Repeatable Reads | Phantom Reads |
|----------------|---------------------|---------------|
| READ COMMITTED | ✅ Allowed          | ✅ Allowed    |
| REPEATABLE READ| ❌ Prevented         | ❌ Prevented* |

*MySQL's Repeatable Read prevents phantom reads using Next-Key Locking

## Next Steps

1. Run the basic experiments above to understand core concepts
2. Try the advanced scenarios to see edge cases
3. Experiment with real-world examples to see practical applications
4. Compare isolation levels to understand trade-offs
5. Explore MySQL-specific behavior to understand implementation details

