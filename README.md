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
- Clingon CLI: `focus` (local, server host) and `focus-cli` (remote REST client)

## Tech Stack

| Component   | Choice                        |
|-------------|-------------------------------|
| Language    | Common Lisp                   |
| Server      | Clack + Wookie                |
| Database    | PostgreSQL                    |
| WebSocket   | websocket-driver              |
| CLI         | Clingon — `focus` (local), `focus-cli` (remote REST client) |
| Frontend    | ClojureScript + Reagent (re-frame) |
| Hot reload  | nREPL (port 5000)             |
| Build       | Makefile + ASDF `program-op`  |
| Testing     | FiveAM (backend), cljsbuild (frontend) |

## Quick start

```bash
make build          # build binaries: build/focus and build/focus-cli
make tests          # run the backend test suite
./build/focus       # start the server (config from ./focus.conf)
```

Copy `focus.conf.template` to `focus.conf` and fill in your database and
OAuth2 settings first. See `docs/CONFIG.md`.

## CLI

Two binaries, both Clingon:

**`focus`** — web server + local CLI. Running `focus` with no subcommand
starts the web server; subcommands run against the PostgreSQL database on
the server host. `--rebuild-db` drops and re-creates the schema.

```bash
focus list   [--status open] [--priority high] [--board ID]
focus create --title "Bug report" [--description "Details..."] \
             [--status open] [--priority medium] [--assignee ID] [--color "#e74c3c"]
             [--board ID]
focus update <id> [--title ...] [--description ...] [--status closed]
                   [--priority low] [--assignee ID] [--color ...]
focus delete <id>
```

**`focus-cli`** — remote REST client. Runs from any machine; authenticates
with a stored agent API key (`Authorization: Bearer`), no database access.
Config lives in `~/.focus-cli`.

```bash
focus-cli add-site --name work --url http://host:8080 \
                   --key "focusN-..."          # one key per site
focus-cli add-board --site work                 # pick boards interactively
focus-cli add-board --site work --board Helpdesk --name hd   # alias hd -> Helpdesk
focus-cli list-sites                            # sites + board aliases
focus-cli list-boards --site work               # aliases + server boards
focus-cli list --board work/helpdesk [--status open]  # site + board in one
focus-cli list --board hd [--status open]       # by local alias
focus-cli create --title "Deploy" --board work/helpdesk \
                 [--description "Details"] [--priority high] [--status open] \
                 [--assignee ID] [--color "#e74c3c"]
focus-cli show 1 --site work                    # explicit site
focus-cli comment add 1 --site work --body "Looking into it"
```

`~/.focus-cli` holds several named **sites** — each a server URL + key (the
key is per site) + any number of **board aliases** from that server. `add-site
--name NAME --url URL --key KEY` adds or updates one; there is no active site.
`add-board` fetches the boards the agent can see on that server and stores
aliases (interactive picker if `--board` is omitted; `--name` sets a shorter
local alias). A site's server URL is its separator: boards named the same on
different servers don't collide.

Every command names its target explicitly: `list`/`create` take a mandatory
`--board SITE/BOARD` (a local alias, remote name, or numeric id);
`show`/`update`/`delete`/`comment`/`label`/`add-board`/`list-boards` take a
mandatory `--site NAME`. `FOCUS_BOARD` supplies the board for `list`/`create`;
`FOCUS_SITE` supplies the site for the rest. Boards are stored **by name** and
re-resolved against their server on each command (rename-safe).

See `docs/PROJECT.md` for the full command reference for both binaries.

## Documentation

- `docs/ARCHITECTURE.md` — source layout, ASDF systems, static embedding
- `docs/DATABASE.md` — connection, migrations, schema
- `docs/API.md` — REST endpoints
- `docs/BUILD.md` — build & run, hot reload, systemd install
- `docs/CONFIG.md` — configuration file format and keys

## License

GPL-3.0-or-later. See `LICENSE`.
