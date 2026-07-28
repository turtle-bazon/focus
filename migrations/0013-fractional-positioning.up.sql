ALTER TABLE tickets ADD COLUMN position_num INTEGER DEFAULT 0;
ALTER TABLE tickets ADD COLUMN position_den INTEGER DEFAULT 1;

UPDATE tickets SET position_num = position, position_den = 1;

ALTER TABLE tickets DROP COLUMN position;
