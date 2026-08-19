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
| CLI | Clingon (`src/cli/commands.lisp`, root handler is the web server) |
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

## Docs Index

- `docs/ARCHITECTURE.md` — source layout, ASDF systems, dependencies, static embedding
- `docs/DATABASE.md` — connection, migrations, schema
- `docs/API.md` — REST endpoints
- `docs/BUILD.md` — build & run, hot reload
- `docs/CONFIG.md` — configuration file format and keys
- `AGENTS.md` — operating rules for agents working on this repo
