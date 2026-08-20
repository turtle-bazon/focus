# Focus — REST API

All routes are dispatched in `src/api/routes.lisp`. Handlers live in
`src/api/handlers.lisp`. Path parameters are denoted with `:id`; `.id`-less
trailing segments (e.g. group/board member refs, transitions) are matched by
regex and typically resolve a user/group/status by name or id.

## Auth

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/auth/login | Start OpenID/OAuth2 login |
| GET | /api/auth/callback | OAuth2 callback |
| GET | /api/auth/me | Current user profile |
| POST | /api/auth/logout | Log out |

## App

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/app/info | App name / description / oauth2_configured |

## Tickets

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/tickets | List tickets (paginated, filterable, sortable) |
| POST | /api/tickets | Create ticket |
| GET | /api/tickets/search | Full-text search tickets |
| GET | /api/tickets/:id | Get ticket |
| PUT | /api/tickets/:id | Update ticket |
| DELETE | /api/tickets/:id | Delete ticket |
| GET | /api/tickets/:id/comments | List comments |
| POST | /api/tickets/:id/comments | Add comment |
| GET | /api/tickets/:id/activity | List activity |
| GET | /api/tickets/:id/observers | List observers |
| POST | /api/tickets/:id/observers | Add observer |
| DELETE | /api/tickets/:id/observers/:ref | Remove observer |

## Users

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/users | List users |
| POST | /api/users | Create user |
| PUT | /api/users/:id | Update user |
| DELETE | /api/users/:id | Soft-delete user |
| POST | /api/users/:id/undelete | Restore soft-deleted user |

## Labels

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/labels | List labels |
| POST | /api/labels | Create label |

## Attachments

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/attachments/:id | Get attachment |

> Note: `create-attachment` exists in the model, but no upload HTTP route is
> wired in `routes.lisp` currently.

## Webhooks

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/webhooks | List webhooks |
| POST | /api/webhooks | Create webhook |

## Groups

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/groups | List groups |
| POST | /api/groups | Create group |
| GET | /api/groups/:id | Get group |
| PUT | /api/groups/:id | Update group |
| DELETE | /api/groups/:id | Delete group |
| GET | /api/groups/:id/members | List members |
| POST | /api/groups/:id/members | Add member |
| DELETE | /api/groups/:id/members/:user-id | Remove member |

## Activity

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/activity | Combined activity across all visible boards |

## Boards

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/boards | List boards |
| POST | /api/boards | Create board |
| GET | /api/boards/:id | Get board |
| PUT | /api/boards/:id | Update board |
| DELETE | /api/boards/:id | Delete board |
| GET | /api/boards/:id/activity | Board activity |
| GET | /api/boards/:id/transitions | List transitions |
| POST | /api/boards/:id/transitions | Add transition |
| DELETE | /api/boards/:id/transitions/:ref | Remove transition |
| GET | /api/boards/:id/statuses | List statuses |
| POST | /api/boards/:id/statuses | Create status |
| PUT | /api/boards/:id/statuses/:status-id | Update status |
| DELETE | /api/boards/:id/statuses/:status-id | Delete status |
| GET | /api/boards/:id/members | List members |
| POST | /api/boards/:id/members | Add member |
| DELETE | /api/boards/:id/members/:ref | Remove member |

## Agents

Agents are non-human identities owned by a user. They authenticate through
the encrypted envelope endpoint below, not with plain bearer calls.

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/agents | List the acting user's agents |
| POST | /api/agents | Create agent |
| GET | /api/agents/:id | Get agent |
| PUT | /api/agents/:id | Update agent |
| DELETE | /api/agents/:id | Delete agent |
| GET | /api/agents/:id/shapes | List credential shapes |
| POST | /api/agents/:id/shapes | Create credential shape |
| DELETE | /api/agents/:id/shapes/:shape-id | Revoke shape |

`POST /api/agents/:id/shapes` returns the credentials **once**:

```json
{"id": 5, "bearer": "focus3-...", "server_public": "BASE64",
 "agent_private": "BASE64", "agent_id": 3}
```

The server stores only the SHA-256 hash of the bearer plus its own X25519
private key and the agent's public key (`agent_key_shapes` table).

### Agent envelope: `POST /api/agent`

All agent API traffic is tunneled through this endpoint. The caller sends
`Authorization: Bearer <bearer>` and a JSON envelope body:

```json
{"v": 1, "ts": 1700000000, "n": "BASE64", "ct": "BASE64", "tg": "BASE64"}
```

- Both sides derive the same 32-byte shared secret via X25519 ECDH:
  server = DH(server_private, agent_public), client = DH(agent_private,
  server_public). A per-shape master key is HMAC-SHA256(secret, label).
- Each message derives a fresh AES-256-GCM session key from the master key,
  direction ("request"/"response"), timestamp, and nonce; the direction and
  timestamp are also bound as associated data.
- The decrypted request plaintext is
  `{"method": "...", "path": "/api/...", "query": "...", "body": "JSON-or-null"}`;
  the inner request is dispatched to the regular router as the shape's agent.
- The response plaintext is `{"status": N, "body": "JSON"}`; the outer HTTP
  status mirrors the inner one.
- Timestamps must be within `envelope-window-seconds` (default 15) of server
  time; tampered envelopes fail tag verification (401).

## Static / SPA

Non-API `GET` requests fall through to embedded static assets. Deep routes
that are not real files fall back to `index.html` for the SPA:

`/`, `/activity`, `/settings`, `/tickets/:id`, `/tickets/:id/activity`,
`/boards/:id`, `/boards/:id/activity`.