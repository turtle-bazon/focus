ALTER TABLE tickets DROP COLUMN IF EXISTS board_id;
DROP TABLE IF EXISTS board_transitions;
DROP TABLE IF EXISTS board_statuses;
DROP TABLE IF EXISTS board_members;
DROP TABLE IF EXISTS boards;