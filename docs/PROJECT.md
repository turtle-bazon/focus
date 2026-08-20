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
| CLI | Clingon — `focus` (`src/cli/commands.lisp`, root handler is the web server); `focus-cli` (`src/cli/remote.lisp`, REST client) |
| Frontend | ClojureScript + Reagent (re-frame) |
| Hot reload | nREPL (port 5000) |
| Build | Makefile + ASDF `program-op` |
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

Defined in `src/cli/commands.lisp`. Running `focus` with no subcommand
starts the web server; subcommands run against the database configured in
`config.json`. The documented command interface is:

```bash
# List tickets
focus list [--status open] [--priority high] [--assignee ID] [--board ID]
            [--limit N] [--page N] [--search QUERY] [--json]

# Show ticket details (labels + comments)
focus show 123 [--json]

# Create ticket
focus create --title "Bug report" --description "Details..." \
             [--priority high] [--status open] [--board ID] [--assignee ID]

# Update ticket
focus update 123 --status closed --priority low --title "New title"

# Delete ticket
focus delete 123

# Comments
focus comment add 123 --body "Looking into it" --agent 2
focus comment list 123
focus comment delete 456

# Labels
focus label list
focus label create --name "backend" --color "#e74c3c"
focus label add 123 2
focus label remove 123 2

# Agents & boards (setup for a bot/agent)
focus user list
focus agent create --name "ci-bot" --owner 1 --description "CI" --key
focus agent list
focus agent key add 3            # generate a new API key (shown once)
focus agent key list 3
focus agent key revoke 3 5
focus agent delete 3

focus board create --name "Project" --type common --owner 1
focus board list
focus board members 7
focus board member add 7 --agent 3
focus board member remove 7 --agent 3
focus board delete 7
```

For a single scripted agent that owns its workflow, store its identity once and
let every later command default to it:

```bash
# Bootstrap: creates agent + board + API key, saves identity to ~/.focus-cli
focus agent init --owner 1 --name "dev-agent" --board "Work"

# Or adopt an agent/board created in the web UI:
focus agent use --agent 3 --board 7 --key "focus3-..."

focus status              # review stored agent/board/key
focus list                # defaults to the stored board
focus create --title "Deploy"    # defaults to the stored board
focus comment add 15 --body "checking"   # defaults to the stored agent
```

Note: subcommands connect directly to the PostgreSQL database configured in
`focus.conf` — run them on the same host as the server. API keys (`focusN-...`)
are shown only once, so store them securely; agents authenticate against the
REST API with `Authorization: Bearer <key>`.

## Remote CLI (`focus-cli`)

`focus-cli` is a second binary defined in `src/cli/remote.lisp`. It talks to
the server's REST API using a stored agent API key (`Authorization: Bearer`),
has **no database access**, and runs from any machine. Its config lives in
`~/.focus-cli`; bootstrap it with `focus agent init`/`focus agent use` (above),
or manually:

```bash
focus-cli add-site --name work --url http://host:8080 --key "focusN-..." \
                   [--agent ID]                       # server URL + key
focus-cli add-board --site work --board Helpdesk      # one board by name
focus-cli add-board --site work --name hd --board Helpdesk  # local alias
focus-cli add-board --site work                       # interactive picker
focus-cli list-sites                                  # sites + board aliases
focus-cli list-boards --site work                     # aliases + server boards

focus-cli list --board work/helpdesk [--status open] [--priority high]
               [--assignee ID] [--limit N] [--page N] [--search QUERY] [--json]
focus-cli create --title "Bug report" --description "Details..." \
                 --board work/helpdesk [--priority high] [--status open]
                 [--assignee ID] [--color "#e74c3c"]
focus-cli show 1 --site work [--json]
focus-cli update 1 --site work [--title ...] [--description ...] [--status closed]
                   [--priority low] [--assignee ID] [--color ...]
focus-cli delete 1 --site work

focus-cli comment add 1 --site work --body "Looking into it"
focus-cli comment list 1 --site work
focus-cli comment delete 1 2 --site work

focus-cli label list --site work
focus-cli label add 1 2 --site work
focus-cli label remove 1 2 --site work
```

`~/.focus-cli` holds several named **sites** — each a server URL + agent API
key (the key is per site) + any number of **board aliases** from that server.
`add-site --name NAME --url URL --key KEY` adds or updates a site; there is
no single "active site". The server URL is what separates sites — boards
named the same on different servers don't collide.

`add-board --site NAME` fetches the boards the agent can see and prompts you
to pick several interactively (numbers/names, space or comma separated, empty
for all), asking for a local alias per board (defaults to the remote name).
Pass `--board REMOTE-NAME` to add one deterministically, optionally with a
local alias via `--name`. `list-sites` shows every site with its board aliases;
`list-boards --site NAME` shows the aliases plus every board the agent can see
on that server.

Every API command names its server and board explicitly, never implicitly:
`list`/`create` take a mandatory `--board SITE/BOARD` (a local alias, the
remote name, or a numeric id — everything resolves against that site's server);
all other commands take a mandatory `--site NAME`. `FOCUS_BOARD` supplies the
board for `list`/`create`, and `FOCUS_SITE` supplies the site for the rest.
`comment add` acts as the stored agent. Unlike `focus`, the remote CLI
supports only ticket, comment, label, and board operations — agent management
stays on the server host with `focus agent ...`.

## Docs Index

- `docs/ARCHITECTURE.md` — source layout, ASDF systems, dependencies, static embedding
- `docs/DATABASE.md` — connection, migrations, schema
- `docs/API.md` — REST endpoints
- `docs/BUILD.md` — build & run, hot reload
- `docs/CONFIG.md` — configuration file format and keys
- `AGENTS.md` — operating rules for agents working on this repo
