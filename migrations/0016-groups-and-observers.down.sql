DROP TABLE IF EXISTS ticket_observers;
ALTER TABLE tickets DROP COLUMN IF EXISTS assignee_type;
DROP TABLE IF EXISTS group_members;
DROP TABLE IF EXISTS groups;
