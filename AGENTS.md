# AGENTS.md — focus

## Project

Ticket tracker. Create, manage, and track tickets with labels, assignees, and status.

## Tech Stack

| Component | Choice |
|-----------|--------|
| Language | Common Lisp |
| Server | Clack + Wookie |
| Database | PostgreSQL |
| WebSocket | websocket-driver |
| CLI | Clingon |
| Frontend | ClojureScript + Reagent |
| Hot reload | nREPL (port 5000) |
| Build | buildapp + Makefile |
| Testing | FiveAM |

## Database

- **Connection**: `psql -h 127.0.0.1 -U focus -W focus`
- **Host**: 127.0.0.1
- **Database**: focus
- **User**: focus
- **Password**: focus

### Migrations

SQL migration files live in `migrations/`. Run `make generate-migrations` to regenerate `src/migrations.lisp` which embeds all SQL into the binary. The embedded migrations run automatically on server startup via `migrate-up`.

### Schema

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE tickets (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(20) DEFAULT 'open',
    priority VARCHAR(10) DEFAULT 'medium',
    assignee_id INTEGER REFERENCES users(id),
    position INTEGER DEFAULT 0,
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
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/tickets | List tickets (paginated, filterable, sortable) |
| GET | /api/tickets/:id | Get ticket by ID |
| POST | /api/tickets | Create new ticket |
| PUT | /api/tickets/:id | Update ticket |
| DELETE | /api/tickets/:id | Delete ticket |
| GET | /api/tickets/:id/comments | List comments on ticket |
| POST | /api/tickets/:id/comments | Add comment to ticket |
| GET | /api/tickets/:id/activity | List activity for ticket |
| GET | /api/tickets/search | Full-text search tickets |
| GET | /api/users | List all users |
| POST | /api/users | Create user |
| GET | /api/labels | List all labels |
| POST | /api/labels | Create label |
| GET | /api/attachments/:id | Get attachment |
| POST | /api/tickets/:id/attachments | Upload attachment |
| GET | /api/webhooks | List webhooks |
| POST | /api/webhooks | Create webhook |

## CLI Commands

```bash
# List tickets
focus list [--status open] [--priority high]

# Create ticket
focus create --title "Bug report" --description "Details..."

# Update ticket
focus update 123 --status closed --priority low

# Delete ticket
focus delete 123
```

## Frontend

Design: **simple but sexy** — clean lines, minimal chrome, good typography. Not generic Bootstrap. Think: a ticket tracker that looks premium.

ClojureScript + Reagent in `frontend/`:

```
frontend/
├── project.clj              # Leiningen project
└── src/
    └── focus/
        ├── core.cljs         # Entry point, router
        ├── views.cljs        # Reagent components
        ├── handlers.cljs     # Re-frame events
        ├── subs.cljs         # Re-frame subscriptions
        └── api.cljs          # HTTP client for REST API
```

Auto updates via WebSocket — tickets, comments, and activity update in real-time without page refresh.

Kanban board view with drag-and-drop between columns: `Backlog → Open → In Progress → Review → Done`. Cards show tags (labels) with colors for quick visual identification.

```
focus/
├── AGENTS.md
├── Makefile
├── focus.asd
├── focus-tests.asd
├── build.lisp
├── migrations/
│   ├── 0001-schema-version.{up,down}.sql
│   ├── 0002-users-table.{up,down}.sql
│   ├── 0003-issues-table.{up,down}.sql
│   ├── 0004-labels-table.{up,down}.sql
│   ├── 0005-issue-labels.{up,down}.sql
│   ├── 0006-comments-table.{up,down}.sql
│   ├── 0007-activity-table.{up,down}.sql
│   ├── 0008-attachments-table.{up,down}.sql
│   ├── 0009-webhooks-table.{up,down}.sql
│   ├── 0010-sessions-table.{up,down}.sql
│   ├── 0011-issues-position.{up,down}.sql
│   └── 0012-rename-issues-to-tickets.{up,down}.sql
├── src/
│   ├── package.lisp
│   ├── config.lisp
│   ├── migrations.lisp
│   ├── db.lisp
│   ├── nrepl.lisp
│   ├── models/
│   │   ├── user.lisp
│   │   ├── ticket.lisp
│   │   ├── label.lisp
│   │   ├── comment.lisp
│   │   ├── activity.lisp
│   │   ├── attachment.lisp
│   │   └── webhook.lisp
│   ├── api/
│   │   ├── routes.lisp
│   │   └── handlers.lisp
│   ├── cli/
│   │   └── commands.lisp
│   └── main.lisp
├── t/
│   ├── api-tests.lisp
│   ├── model-tests.lisp
│   └── cli-tests.lisp
├── tools/
│   └── build-migrations.lisp
└── frontend/
    ├── project.clj
    └── src/
        └── focus/
            ├── core.cljs
            ├── views.cljs
            ├── handlers.cljs
            ├── subs.cljs
            └── api.cljs
```

## Build & Run

```bash
make build          # Build binary to build/focus
make dev-start      # Run in background
make dev-stop       # Stop background process
make clean          # Remove build/
make tests          # Run test suite
make generate-migrations  # Regenerate migrations.lisp from SQL files
```

## ASDF System Definition

```lisp
(defsystem :focus
  :name "focus"
  :license "TBD"
  :version "0.0.1.0"
  :description "Ticket tracker"
  :depends-on (#:clack
               #:clack-handler-wookie
               #:websocket-driver
               #:cl-json
               #:postmodern
               #:cl-postgres+local-time
               #:iterate
               #:cl-bazon
               #:bazon-log
               #:metabang-bind
               #:clingon
               #:usocket
               #:bordeaux-threads
               #:uiop
               #:dexador
               #:cl-openid)
  :serial t
  :components ((:module "src"
                :components
                 ((:file "package")
                  (:file "config")
                  (:file "migrations")
                  (:file "db")
                  (:file "nrepl")
                  (:module "models"
                   :components ((:file "user")
                                 (:file "ticket")
                                (:file "label")
                                (:file "comment")
                                (:file "activity")
                                (:file "attachment")
                                (:file "webhook")))
                  (:module "api"
                   :components ((:file "routes")
                                (:file "handlers")))
                  (:module "cli"
                   :components ((:file "commands")))
                  (:file "main")))))

## Test System Definition

```lisp
(defsystem :focus-tests
  :name "focus-tests"
  :description "Tests for focus"
  :depends-on (#:focus
               #:fiveam)
  :serial t
  :components ((:module "t"
                :components ((:file "api-tests")
                             (:file "model-tests")
                             (:file "cli-tests")))))
```

## Hot Reload

Server runs nREPL on 127.0.0.1:5000. Connect via Emacs SLIME or terminal and load changed files.

**NEVER restart server just to reload code** — use hot-load.
Only restart for initial startup or when nREPL is down.

## Config

S-expression plist, searched in order:
1. `./focus.conf`
2. `~/.focus.conf`
3. `~/.config/focus/focus.conf`
4. `/etc/focus.conf`

```lisp
(:db-host "127.0.0.1"
 :db-name "focus"
 :db-user "focus"
 :db-pass "focus"
 :bind-address "0.0.0.0"
 :bind-port 8080
 :nrepl-port 5000
 :nrepl-address "127.0.0.1")
```

## Conventions

- Follow link-short patterns where applicable
- ASDF system definition with `:serial t`
- Config via S-expression plist
- **No large functions**: Maximum 50 lines per function
- **SQL**: Use parametric queries only (`query (:select ... :where (:= ... $1)) value`). Never use string concatenation for SQL.
- **Iteration**: Use `:iterate` library for all iteration. Use `iter` macro with clauses like `(for x in list)`, `(for x in-vector vec)`, `(collecting ...)`, `(while cond)`. Never use `loop`, `dolist`, `dotimes`, `mapcar`, or `maphash`.
- **Binding**: Use `metabang-bind` for destructuring
- **Testing**: Use FiveAM for all tests
- **Validation**: Run cl-validation on all .lisp files before proceeding
- **Mercurial**: Always use `hg mv` instead of `mv` when moving files. This keeps hg's dirstate clean.
- **Commits**: Never commit without user approval. Always ask first.

## Mattermost Integration

- **Bot**: Mattermost bot for notifications and commands
- **OpenID**: Mattermost as OpenID Connect provider for authentication

## Dependencies

```lisp
:clack              ; Web server
:lack               ; WSGI-like interface
:clack-handler-wookie ; Wookie handler
:websocket-driver   ; WebSocket support
:cl-json            ; JSON parsing
:postmodern         ; PostgreSQL adapter
:cl-postgres+local-time ; PostgreSQL + time
:iterate            ; Iteration constructs
:cl-bazon           ; Utility libraries
:bazon-log          ; Logging
:metabang-bind      ; Binding/destructuring
:clingon            ; CLI argument parsing
:usocket            ; TCP sockets
:bordeaux-threads   ; Threading
:uiop               ; Utilities
:fiveam             ; Testing (focus-tests only)
:dexador            ; HTTP client
:cl-openid          ; OpenID Connect support
```

# Agent Memory Protocol

You have access to a persistent knowledge graph via MCP memory tools (`create_entities`, `add_observations`, `search_nodes`, `read_graph`).

## Startup Workflow
- At the start of a session or complex task, query `search_nodes` or `read_graph` to retrieve relevant project rules, architectural decisions, or known gotchas.

## Active Recall & Persistence Rules
- **When learning something new:** If the user establishes a project constraint, coding standard, or fixes a tricky bug, immediately invoke `create_entities` or `add_observations` to save it to memory.
- **When starting a refactor:** Search memory for existing components, dependencies, or past decisions before making breaking changes.
