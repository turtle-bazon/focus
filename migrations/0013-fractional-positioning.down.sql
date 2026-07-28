ALTER TABLE tickets ADD COLUMN position INTEGER DEFAULT 0;

UPDATE tickets SET position = 0;

ALTER TABLE tickets DROP COLUMN position_num;
ALTER TABLE tickets DROP COLUMN position_den;
