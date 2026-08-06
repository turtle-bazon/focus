# Focus — Configuration

Config is a single S-expression plist read from the first existing file of:

1. `./focus.conf`
2. `~/.focus.conf`
3. `~/.config/focus/focus.conf`
4. `/etc/focus.conf`

Accessors live in `src/config.lisp`; discovery/validation in
`find-config` / `read-config` / `validate-config`.

## Example

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

## Keys

| Key | Default | Description |
|-----|---------|-------------|
| `:db-host` | (required) | PostgreSQL host |
| `:db-port` | 5432 | PostgreSQL port |
| `:db-name` | (required) | Database name |
| `:db-user` | (required) | Database user |
| `:db-pass` | (required) | Database password |
| `:bind-address` | nil → "0.0.0.0" | HTTP bind address |
| `:bind-port` | (required) | HTTP port |
| `:nrepl-port` | nil | nREPL port (off if nil) |
| `:nrepl-address` | "127.0.0.1" | nREPL bind address |

### OAuth2 / OpenID (Mattermost)

| Key | Default | Description |
|-----|---------|-------------|
| `:oauth2-client-id` | nil | OAuth2 client ID |
| `:oauth2-client-secret` | nil | OAuth2 client secret |
| `:oauth2-authorize-uri` | nil | Authorization endpoint |
| `:oauth2-token-uri` | nil | Token endpoint |
| `:oauth2-redirect-uri` | nil | Redirect URI |
| `:oauth2-scopes` | ("openid" "profile" "email") | Requested scopes |
| `:oauth2-userinfo-uri` | nil | Userinfo endpoint |
| `:oauth2-userinfo-email-key` | "email" | Userinfo claim for email |
| `:oauth2-userinfo-username-key` | "username" | Userinfo claim for username |
| `:oauth2-userinfo-name-key` | "name" | Userinfo claim for display name |
| `:oauth2-userinfo-picture-key` | "picture" | Userinfo claim for avatar |

### App branding

| Key | Default | Description |
|-----|---------|-------------|
| `:app-name` | "Focus" | Landing page title |
| `:app-description` | "Issue tracker" | Landing page description |

> There is **no** `:static-dir` key — static assets are embedded into the
> binary image (see `docs/ARCHITECTURE.md`).