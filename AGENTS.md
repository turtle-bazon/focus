# AGENTS.md — focus

Operating rules for agents working on Focus, a Kanban-style ticket tracker
(Common Lisp backend + ClojureScript/Reagent frontend). Licensed
GPL-3.0-or-later — see `LICENSE`; keep the SPDX header on every source file.

## Documentation

Read the docs before working:

- `docs/PROJECT.md` — overview, tech stack, Mattermost, CLI
- `docs/ARCHITECTURE.md` — source layout, ASDF systems, static embedding
- `docs/DATABASE.md` — connection, migrations, schema
- `docs/API.md` — REST endpoints
- `docs/BUILD.md` — build & run, tests, hot reload
- `docs/CONFIG.md` — config file format and keys

## Conventions

- **No large functions**: maximum 50 lines per function.
- **SQL**: parametric queries only (`query (:select ... :where (:= ... $1)) value`).
  Never string-concatenate SQL.
- **Iteration**: use `:iterate` — `iter` with `(for x in ...)`, `(collecting ...)`,
  `(while ...)`. Never `loop`, `dolist`, `dotimes`, `mapcar`, or `maphash`.
- **Binding**: use `metabang-bind` for destructuring.
- **Testing**: FiveAM for all tests. `make tests` runs the suite.
- **Validation**: run cl-validation on all `.lisp` files before proceeding.
- **Mercurial**: always use `hg mv` when moving files (keeps dirstate clean).
- **Commits**: never commit without user approval. Always ask first.

## Static Assets

Static assets (frontend JS/CSS/HTML/IMG) are **embedded into the binary** —
no `static-dir` config, no runtime filesystem reads. `make generate-static`
base64-encodes `build/static/` into `src/static-assets.lisp` (generated, do
not edit); `src/static.lisp` decodes on demand. `build` runs it automatically.

Frontend hot reload without a server rebuild:

```lisp
(focus:reload-static-assets "frontend/resources/public/")
```

If `src/static.lisp` or `src/package.lisp` changed, hot-load those first via
nREPL, then reload assets.

## Hot Reload

Server runs a **line-based** nREPL on `127.0.0.1:5000` (not bencode nREPL) —
send Lisp forms as newline-terminated lines.

**NEVER restart the server just to reload code** — hot-load changed files.
Only restart for initial startup or when nREPL is down.

## Frontend

- ClojureScript + Reagent/re-frame in `frontend/`. Design: **simple but sexy**.
- Editor/markdown live in `frontend/src/focus/views.cljs` and `markdown.cljs`.
- `editor-sync-content` locates the editor via the current window selection;
  if focus is elsewhere (e.g. a modal), it silently skips its callback — when
  inserting into the editor, restore the selection first.
- Lucide icons: `lucide.icons` must stay unmangled (`resources/lucide.ext.js`);
  `lucide.createElement` returns a real SVG DOM element.
- Frontend tests: `lein cljsbuild once test` then `node target/test.js`.
