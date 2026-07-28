CREATE TABLE sessions (
    id VARCHAR(64) PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT now(),
    expires_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_sessions_expires ON sessions(expires_at);
