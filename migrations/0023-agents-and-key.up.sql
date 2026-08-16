CREATE TABLE IF NOT EXISTS agents (
    id SERIAL PRIMARY KEY,
    owner_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_agents_owner ON agents(owner_id);

CREATE TABLE IF NOT EXISTS agent_keys (
    id SERIAL PRIMARY KEY,
    agent_id INTEGER REFERENCES agents(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL,
    created_at TIMESTAMP DEFAULT now(),
    last_used_at TIMESTAMP,
    revoked BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_agent_keys_hash ON agent_keys(token_hash);
CREATE INDEX IF NOT EXISTS idx_agent_keys_agent ON agent_keys(agent_id);

ALTER TABLE board_members DROP CONSTRAINT board_members_member_type_check;
ALTER TABLE board_members ADD CONSTRAINT board_members_member_type_check
  CHECK (member_type IN ('user', 'group', 'agent'));

ALTER TABLE ticket_observers DROP CONSTRAINT ticket_observers_observer_type_check;
ALTER TABLE ticket_observers ADD CONSTRAINT ticket_observers_observer_type_check
  CHECK (observer_type IN ('user', 'group', 'agent'));

ALTER TABLE activity ADD COLUMN IF NOT EXISTS agent_id INTEGER REFERENCES agents(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_activity_agent ON activity(agent_id);

ALTER TABLE comments ADD COLUMN IF NOT EXISTS agent_id INTEGER REFERENCES agents(id) ON DELETE SET NULL;