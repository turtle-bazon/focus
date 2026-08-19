# Focus — Build & Run

## Targets

```bash
make build          # Build binaries: build/focus and build/focus-cli
make dev-start      # Run in background (nohup ./build/focus)
make dev-stop       # Stop background process
make clean          # Remove build/
make tests          # Run backend test suite (FiveAM)
make generate-migrations  # Regenerate src/migrations.lisp from migrations/
make generate-static      # Regenerate src/static-assets.lisp from build/static/
```

`build` runs `clean prepare frontend generate-static` then invokes
`sbcl --non-interactive --load build.lisp`, which quickloads `:focus` and
calls `(asdf:make "focus")` followed by `(asdf:make "focus-cli")`. Each
system's `program-op` (`:build-operation`, `:build-pathname`, `:entry-point`)
produces an executable: `build/focus` (web server + local CLI) and
`build/focus-cli` (remote REST client). `BUILD_SUFFIX` is honored for the
`focus` output name.

The binaries are embedded and self-contained: static is baked into the image,
so no `static-dir` config and no runtime filesystem reads are needed.

## Install as a systemd service

A ready-to-use unit file lives at `deploy/focus.service`. To install:

```bash
make build
sudo install -m 755 build/focus /usr/local/bin/focus
sudo install -m 640 focus.conf /etc/focus.conf          # config is read from /etc/focus.conf
sudo useradd --system --home /var/lib/focus focus        # unused system user
sudo install -m 755 deploy/focus.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now focus
```

Adjust the `ExecStart`/`User`/config paths in `deploy/focus.service` to match
your install layout.

## Frontend

The ClojureScript app builds with Leiningen `cljsbuild`:

```bash
cd frontend
lein cljsbuild once min     # optimizations :advanced, ext: lucide.ext.js
lein cljsbuild once test     # build tests, then: node target/test.js
```

`lein cljsbuild once min` writes `frontend/resources/public/js/app.js`.
The `min` build's `:externs` protect `lucide.icons` from Closure mangling.

## Tests

```bash
make tests   # backend FiveAM suite (focus-tests)
```

## Hot Reload (nREPL)

Server runs a line-based nREPL on `127.0.0.1:5000`. Connect with a terminal
or SLIME and send Lisp forms as newline-terminated lines.

**NEVER restart the server just to reload code** — hot-load instead. Only
restart for initial startup or when nREPL is down.

To serve newly compiled frontend without rebuilding the server:

```lisp
(focus:reload-static-assets "frontend/resources/public/")
```

If `static.lisp` / `package.lisp` have new symbols, hot-load those files first
via nREPL (`(load #P"...")`), then reload your frontend assets.