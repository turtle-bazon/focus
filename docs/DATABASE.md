# Focus — Database

## Connection

- **Host**: 127.0.0.1
- **Database**: focus
- **User**: focus
- **Password**: focus
- **CLI**: `psql -h 127.0.0.1 -U focus -W focus`

## Migrations

SQL migration files live in `migrations/` (`0001` .. `0025`). Run
`make generate-migrations` to regenerate `src/migrations.lisp`, which embeds
all SQL into the binary. The embedded migrations run automatically on server
startup via `migrate-up`. `migrate-down` exists; `main` supports
`--rebuild-db` (down then up).

Migration subjects: schema_version, users, issues→tickets rename, labels,
issue_labels→ticket_labels, comments, activity, attachments, webhooks,
sessions, position (→ position_num/position_den), ticket color, user picture,
groups + observers, user role, polymorphic assignee (assignee_type), boards
lifecycle, boards default lifecycle, users soft-delete, agents + key shapes,
agent bearer prefix.

## Schema

Final state after all migrations (see `migrations/*.up.sql` for exact DDL):

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    picture VARCHAR(500),
    role VARCHAR(20) DEFAULT 'user',
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE tickets (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(20) DEFAULT 'open',
    priority VARCHAR(10) DEFAULT 'medium',
    assignee_id INTEGER REFERENCES users(id),
    assignee_type VARCHAR(20) DEFAULT 'user',
    board_id INTEGER REFERENCES boards(id) ON DELETE SET NULL,
    color VARCHAR(7) DEFAULT '#6b7280',
    position_num INTEGER DEFAULT 0,
    position_den INTEGER DEFAULT 1,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE labels (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    color VARCHAR(7) DEFAULT '#3498db'
);

CREATE TABLE ticket_labels (
    ticket_id INTEGER REFERENCES tickets(id) ON DELETE CASCADE,
    label_id INTEGER REFERENCES labels(id) ON DELETE CASCADE,
    PRIMARY KEY (ticket_id, label_id)
);

CREATE TABLE comments (
    id SERIAL PRIMARY KEY,
    ticket_id INTEGER REFERENCES tickets(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id),
    body TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE activity (
    id SERIAL PRIMARY KEY,
    ticket_id INTEGER REFERENCES tickets(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id),
    action VARCHAR(50) NOT NULL,
    details JSONB,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE attachments (
    id SERIAL PRIMARY KEY,
    ticket_id INTEGER REFERENCES tickets(id) ON DELETE CASCADE,
    filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(100),
    size INTEGER,
    data BYTEA,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE webhooks (
    id SERIAL PRIMARY KEY,
    url TEXT NOT NULL,
    secret VARCHAR(255),
    events TEXT[] DEFAULT '{}',
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE sessions (
    id VARCHAR(64) PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT now(),
    expires_at TIMESTAMP NOT NULL
);

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

CREATE TABLE ticket_observers (
    ticket_id INTEGER REFERENCES tickets(id) ON DELETE CASCADE,
    observer_type VARCHAR(20) NOT NULL CHECK (observer_type IN ('user', 'group')),
    observer_id INTEGER NOT NULL,
    PRIMARY KEY (ticket_id, observer_type, observer_id)
);

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

CREATE TABLE agents (
    id SERIAL PRIMARY KEY,
    owner_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT now()
);

-- X25519 credential shapes (see src/crypto.lisp). The bearer is stored
-- hashed; the server private half and the agent public half enable the
-- static ECDH shared secret for the POST /api/agent envelope.
CREATE TABLE agent_key_shapes (
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
```
