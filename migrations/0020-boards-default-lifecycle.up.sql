INSERT INTO board_transitions (board_id, from_code, to_code)
SELECT b.id, tr.from_code, tr.to_code
FROM boards b
CROSS JOIN (VALUES
    ('backlog', 'open'),
    ('open', 'in_progress'),
    ('open', 'done'),
    ('in_progress', 'review'),
    ('in_progress', 'open'),
    ('review', 'done'),
    ('review', 'in_progress'),
    ('done', 'open')
) AS tr(from_code, to_code)
WHERE NOT EXISTS (
    SELECT 1 FROM board_transitions bt WHERE bt.board_id = b.id
);

INSERT INTO board_statuses (board_id, code, name, color, position)
SELECT b.id, s.code, s.name, s.color, s.position
FROM boards b
CROSS JOIN (VALUES
    ('backlog', 'Backlog', '#6b7280', 0),
    ('open', 'Open', '#3b82f6', 1),
    ('in_progress', 'In Progress', '#f59e0b', 2),
    ('review', 'Review', '#8b5cf6', 3),
    ('done', 'Done', '#10b981', 4)
) AS s(code, name, color, position)
WHERE NOT EXISTS (
    SELECT 1 FROM board_statuses bs WHERE bs.board_id = b.id
);