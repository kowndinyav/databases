# Step-by-Step Guide: Understanding Repeatable Read

## Step 1: The Core Concept - "Repeatable" Reads

Let's start with the most important concept: **within a transaction, reading the same row twice will always give you the same value**.

### What You'll See:
- Session 1 reads a row
- Session 2 updates that row and commits
- Session 1 reads the same row again → **still sees the old value**
- Session 1 commits → **now** sees the updated value

### Let's Do It:

**Terminal 1 (Session 1):**
```sql
-- First, check what's in the table
SELECT * FROM accounts;

-- Start a transaction
START TRANSACTION;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- Read account with id = 1
SELECT * FROM accounts WHERE id = 1;
-- Note the balance value (write it down!)
```

**Terminal 2 (Session 2):**
```sql
-- While Session 1 is still running, update the balance
UPDATE accounts SET balance = balance + 500 WHERE id = 1;

-- Check what you see
SELECT * FROM accounts WHERE id = 1;
-- You'll see the NEW value (original + 500)
```

**Back to Terminal 1:**
```sql
-- Read the same row again (Session 2 already updated and you can see it committed)
SELECT * FROM accounts WHERE id = 1;
-- What do you see? The OLD value or the NEW value?
-- You should still see the OLD value!

-- Now commit your transaction
COMMIT;

-- Read one more time
SELECT * FROM accounts WHERE id = 1;
-- NOW you'll see the updated value!
```

### Questions to Think About:
1. Why did Session 1 see the old value even after Session 2 committed?
2. What changed after Session 1 committed?

---

**When you're ready, let me know what you observed and we'll move to Step 2!**

