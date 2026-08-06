# Focus — Project Overview

Focus is a Kanban-style ticket tracker for teams. Create, manage, and track
tickets with labels, assignees, observers, and boards. Updates propagate in
real time over WebSocket.

## Tech Stack

| Component | Choice |
|-----------|--------|
| Language | Common Lisp |
| Server | Clack + Wookie |
| Database | PostgreSQL |
| WebSocket | websocket-driver |
| CLI | Clingon (defined in `src/cli/commands.lisp`; not wired into `main`) |
| Frontend | ClojureScript + Reagent (re-frame) |
| Hot reload | nREPL (port 5000) |
| Build | Makefile + `sbcl --load build.lisp` (`sb-ext:save-lisp-and-die`) |
| Testing | FiveAM |

## License

Focus is free software, licensed under the **GNU General Public License
version 3 or (at your option) any later version** (GPL-3.0-or-later). See the
`LICENSE` file at the repository root for the full text.

## Mattermost Integration

- **Bot**: Mattermost bot for notifications and commands
- **OpenID**: Mattermost as OpenID Connect provider for authentication (see `docs/CONFIG.md`)

## Frontend

Design: **simple but sexy** — clean lines, minimal chrome, good typography.
Not generic Bootstrap. Think: a ticket tracker that looks premium.

Auto updates via WebSocket — tickets, comments, and activity update in
real-time without page refresh.

Kanban board view with drag-and-drop between columns. Cards show tags
(labels) with colors for quick visual identification.

## CLI Commands

Defined in `src/cli/commands.lisp` but **not wired into `main`** — the web
server entry point never constructs the root Clingon command. The documented
interface is:

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

## Docs Index

- `docs/ARCHITECTURE.md` — source layout, ASDF systems, dependencies, static embedding
- `docs/DATABASE.md` — connection, migrations, schema
- `docs/API.md` — REST endpoints
- `docs/BUILD.md` — build & run, hot reload
- `docs/CONFIG.md` — configuration file format and keys
- `AGENTS.md` — operating rules for agents working on this repo
