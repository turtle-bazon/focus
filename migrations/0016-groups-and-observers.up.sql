CREATE TABLE groups (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE group_members (
    group_id INTEGER REFERENCES groups(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (group_id, user_id)
);

CREATE INDEX idx_group_members_group ON group_members(group_id);
CREATE INDEX idx_group_members_user ON group_members(user_id);

ALTER TABLE tickets ADD COLUMN assignee_type VARCHAR(20) DEFAULT 'user';

CREATE TABLE ticket_observers (
    ticket_id INTEGER REFERENCES tickets(id) ON DELETE CASCADE,
    observer_type VARCHAR(20) NOT NULL CHECK (observer_type IN ('user', 'group')),
    observer_id INTEGER NOT NULL,
    PRIMARY KEY (ticket_id, observer_type, observer_id)
);

CREATE INDEX idx_ticket_observers_ticket ON ticket_observers(ticket_id);
