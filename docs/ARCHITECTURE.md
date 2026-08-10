# Focus — Architecture

## Repository Layout

```
focus/
├── AGENTS.md               # Operating rules for agents
├── docs/                   # Project documentation
├── Makefile                # build / run / test / generate targets
├── focus.asd               # Main ASDF system
├── focus-tests.asd         # Test ASDF system
├── build.lisp              # Binary build script (save-lisp-and-die)
├── migrations/             # SQL migrations (0001..0021)
├── src/
│   ├── package.lisp        # Package definition + exports
│   ├── config.lisp         # Config accessors, discovery, validation
│   ├── migrations.lisp     # Generated: embedded SQL (do not edit)
│   ├── static-assets.lisp  # Generated: embedded static (do not edit)
│   ├── static.lisp         # Decodes embedded static; reload-static-assets
│   ├── db.lisp             # PostgreSQL connection
│   ├── nrepl.lisp          # Line-based nREPL server (port 5000)
│   ├── ws.lisp             # WebSocket upgrade + broadcast
│   ├── main.lisp           # Entry point (connect DB, migrate, start server)
│   ├── models/             # user, ticket, label, comment, activity,
│   │                       # attachment, webhook, session, group,
│   │                       # ticket-observer, board
│   ├── api/
│   │   ├── routes.lisp     # HTTP router
│   │   ├── auth.lisp       # OAuth2 / session auth
│   │   └── handlers.lisp   # API handlers
│   └── cli/
│       └── commands.lisp   # Clingon CLI (not wired into main)
├── t/
│   ├── package.lisp
│   ├── api-tests.lisp
│   ├── model-tests.lisp
│   └── cli-tests.lisp
├── tools/
│   ├── build-migrations.lisp  # Regenerates src/migrations.lisp
│   └── build-static.lisp      # Regenerates src/static-assets.lisp
└── frontend/
    ├── project.clj            # Leiningen / cljsbuild
    ├── resources/
    │   ├── public/
    │   │   ├── index.html
    │   │   ├── css/style.css
    │   │   ├── js/app.js, js/lucide.min.js
    │   │   └── img/logo.svg
    │   └── lucide.ext.js      # Closure externs for lucide.icons
    └── src/focus/
        ├── core.cljs          # Entry point, router
        ├── views.cljs         # Reagent components, WYSIWYG editor
        ├── handlers.cljs      # re-frame events
        ├── subs.cljs          # re-frame subscriptions
        ├── api.cljs           # HTTP client
        ├── i18n.cljs          # Translations (16 locales)
        ├── markdown.cljs      # Markdown → HTML rendering
        ├── server.cljs
        └── ws.cljs            # WebSocket client
```

## ASDF System

```lisp
(defsystem :focus
  :name "focus"
  :license "GPL-3.0-or-later"
  :version "0.0.1.2"
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
               #:cl-oauth2
               #:cl-base64)
  :serial t
  :components ((:module "src"
                :components
                 ((:file "package")
                  (:file "config")
                  (:file "migrations")
                  (:file "static-assets")
                  (:file "static")
                  (:file "db")
                  (:file "nrepl")
                  (:file "ws")
                  (:module "models"
                   :components ((:file "user")
                                 (:file "ticket")
                                 (:file "label")
                                 (:file "comment")
                                 (:file "activity")
                                 (:file "attachment")
                                 (:file "webhook")
                                 (:file "session")
                                 (:file "group")
                                 (:file "ticket-observer")
                                 (:file "board")))
                  (:module "api"
                   :components ((:file "routes")
                                (:file "auth")
                                (:file "handlers")))
                  (:module "cli"
                   :components ((:file "commands")))
                  (:file "main")))))
```

## Test System

```lisp
(defsystem :focus-tests
  :name "focus-tests"
  :description "Tests for focus"
  :depends-on (#:focus #:fiveam)
  :serial t
  :components ((:module "t"
                :components ((:file "package")
                             (:file "api-tests")
                             (:file "model-tests")
                             (:file "cli-tests")))))
```

## Static Asset Embedding

Static assets (frontend JS/CSS/HTML/IMG) are **embedded into the binary** —
no `static-dir` config, no filesystem reads at runtime.

- `make generate-static` runs `tools/build-static.lisp`, which base64-encodes
  every file under `build/static/` into `src/static-assets.lisp` (generated,
  do not edit).
- `src/static.lisp` decodes them on demand into `*static-assets-cache*`;
  `serve-static-file` streams them from the image.
- The `build` target runs `generate-static` automatically.
- **Hot reload**: `focus:reload-static-assets` (dir `frontend/resources/public/`
  by default) re-reads a directory, re-encodes, swaps the table, and clears the
  cache — call it from nREPL after recompiling the frontend, no server rebuild.