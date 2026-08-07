# Focus

Kanban-style ticket tracker for teams. Create, manage, and track tickets
with labels, assignees, observers, and boards. Updates propagate in real
time over WebSocket.

## Features

- Kanban board view with drag-and-drop between columns
- Tickets, comments, labels, activity, attachments, and webhooks
- Real-time updates via WebSocket (no page refresh)
- Boards and groups with ticket observers
- OpenID Connect authentication (e.g. Mattermost as provider)
- Embedded, self-contained binary — static assets baked into the image
- Line-based nREPL for hot reload while developing
- Clingon CLI with `list` / `create` / `update` / `delete` commands

## Tech Stack

| Component   | Choice                        |
|-------------|-------------------------------|
| Language    | Common Lisp                   |
| Server      | Clack + Wookie                |
| Database    | PostgreSQL                    |
| WebSocket   | websocket-driver              |
| CLI         | Clingon                       |
| Frontend    | ClojureScript + Reagent (re-frame) |
| Hot reload  | nREPL (port 5000)             |
| Build       | Makefile + ASDF `program-op`  |
| Testing     | FiveAM (backend), cljsbuild (frontend) |

## Quick start

```bash
make build          # build the binary to build/focus
make tests          # run the backend test suite
./build/focus       # start the server (config from ./focus.conf)
```

Copy `focus.conf.template` to `focus.conf` and fill in your database and
OAuth2 settings first. See `docs/CONFIG.md`.

## CLI

```bash
focus list   [--status open] [--priority high]
focus create --title "Bug report" --description "Details..."
focus update <id> --status closed --priority low
focus delete <id>
```

Running `focus` with no subcommand starts the web server; `--rebuild-db`
drops and re-creates the schema.

## Documentation

- `docs/ARCHITECTURE.md` — source layout, ASDF systems, static embedding
- `docs/DATABASE.md` — connection, migrations, schema
- `docs/API.md` — REST endpoints
- `docs/BUILD.md` — build & run, hot reload, systemd install
- `docs/CONFIG.md` — configuration file format and keys

## License

GPL-3.0-or-later. See `LICENSE`.
