DROP TABLE IF EXISTS agent_key_shapes;

CREATE TABLE IF NOT EXISTS agent_keys (
    id SERIAL PRIMARY KEY,
    agent_id INTEGER REFERENCES agents(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL,
    token_prefix VARCHAR(32),
    created_at TIMESTAMP DEFAULT now(),
    last_used_at TIMESTAMP,
    revoked BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_agent_keys_hash ON agent_keys(token_hash);
CREATE INDEX IF NOT EXISTS idx_agent_keys_agent ON agent_keys(agent_id);