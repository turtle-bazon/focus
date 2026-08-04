CREATE TABLE boards (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL DEFAULT 'common',
    is_default BOOLEAN NOT NULL DEFAULT false,
    owner_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE board_members (
    board_id INTEGER REFERENCES boards(id) ON DELETE CASCADE,
    member_type VARCHAR(20) NOT NULL CHECK (member_type IN ('user', 'group')),
    member_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT now(),
    PRIMARY KEY (board_id, member_type, member_id)
);

CREATE TABLE board_statuses (
    id SERIAL PRIMARY KEY,
    board_id INTEGER REFERENCES boards(id) ON DELETE CASCADE,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(100) NOT NULL,
    color VARCHAR(7) DEFAULT '#6b7280',
    position INTEGER DEFAULT 0,
    UNIQUE (board_id, code)
);

CREATE TABLE board_transitions (
    id SERIAL PRIMARY KEY,
    board_id INTEGER REFERENCES boards(id) ON DELETE CASCADE,
    from_code VARCHAR(50) NOT NULL,
    to_code VARCHAR(50) NOT NULL,
    UNIQUE (board_id, from_code, to_code)
);

ALTER TABLE tickets ADD COLUMN board_id INTEGER REFERENCES boards(id) ON DELETE SET NULL;
CREATE INDEX idx_tickets_board ON tickets (board_id);

INSERT INTO boards (name, type, is_default) VALUES ('Common', 'common', true);

INSERT INTO board_statuses (board_id, code, name, color, position) VALUES
  (currval('boards_id_seq'), 'backlog', 'Backlog', '#6b7280', 0),
  (currval('boards_id_seq'), 'open', 'Open', '#3b82f6', 1),
  (currval('boards_id_seq'), 'in_progress', 'In Progress', '#f59e0b', 2),
  (currval('boards_id_seq'), 'review', 'Review', '#8b5cf6', 3),
  (currval('boards_id_seq'), 'done', 'Done', '#10b981', 4);

INSERT INTO board_transitions (board_id, from_code, to_code) VALUES
  (currval('boards_id_seq'), 'backlog', 'open'),
  (currval('boards_id_seq'), 'open', 'in_progress'),
  (currval('boards_id_seq'), 'open', 'done'),
  (currval('boards_id_seq'), 'in_progress', 'review'),
  (currval('boards_id_seq'), 'in_progress', 'open'),
  (currval('boards_id_seq'), 'review', 'done'),
  (currval('boards_id_seq'), 'review', 'in_progress'),
  (currval('boards_id_seq'), 'done', 'open');

UPDATE tickets SET board_id = (SELECT id FROM boards WHERE is_default LIMIT 1)
WHERE board_id IS NULL;