When start transaction and update
- always involves 2 locks
- Intent lock
- Row lock

and if for some reason the transaction is not closed, the next modification to the row would get blocked

