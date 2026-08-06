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

## Static / SPA

Non-API `GET` requests fall through to embedded static assets. Deep routes
that are not real files fall back to `index.html` for the SPA:

`/`, `/activity`, `/settings`, `/tickets/:id`, `/tickets/:id/activity`,
`/boards/:id`, `/boards/:id/activity`.