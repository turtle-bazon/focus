ALTER TABLE board_statuses ADD COLUMN IF NOT EXISTS load_count INTEGER NOT NULL DEFAULT 20;
UPDATE board_statuses SET load_count = 5 WHERE code = 'done';