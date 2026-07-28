ALTER TABLE issues ADD COLUMN IF NOT EXISTS position INTEGER DEFAULT 0;

UPDATE issues SET position = sub.new_pos
FROM (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY status ORDER BY created_at DESC) - 1 AS new_pos
  FROM issues
) AS sub
WHERE issues.id = sub.id;
