CREATE TABLE IF NOT EXISTS agent_key_shapes (
    id SERIAL PRIMARY KEY,
    agent_id INTEGER REFERENCES agents(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    bearer_hash VARCHAR(64) NOT NULL,
    token_prefix VARCHAR(32),
    server_private VARCHAR(128) NOT NULL,
    agent_public VARCHAR(128) NOT NULL,
    created_at TIMESTAMP DEFAULT now(),
    last_used_at TIMESTAMP,
    revoked BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_agent_key_shapes_hash ON agent_key_shapes(bearer_hash);
CREATE INDEX IF NOT EXISTS idx_agent_key_shapes_agent ON agent_key_shapes(agent_id);

DROP TABLE IF EXISTS agent_keys;