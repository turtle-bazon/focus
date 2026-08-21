all: build

.PHONY: all build clean prepare frontend dev-start dev-stop tests generate-migrations generate-static focus focus-cli

SBCL_OPTS = sbcl --noinform --non-interactive

# Mark loaded shared objects dont-save so the dumped binary never records
# build-host sonames (libcrypto.so.1.1 vs .so.3); SBCL would otherwise try
# to reopen them by that exact name at startup and die on a target with a
# different OpenSSL. focus::reload-foreign-libraries re-loads everything
# through CFFI at app start, letting candidate lists match the running host.
DONTSAVE_FX = --eval '(dolist (o sb-sys:*shared-objects*) (setf (sb-alien::shared-object-dont-save o) t))'

focus: generate-static
	$(SBCL_OPTS) \
	  --eval '(push :binary *features*)' \
	  --eval '(push (merge-pathnames #P"internal-libs/cl-oauth2/" *default-pathname-defaults*) asdf:*central-registry*)' \
	  --eval '(ql:quickload :focus :silent t)' \
	  $(DONTSAVE_FX) \
	  --eval '(ensure-directories-exist "build")' \
	  --eval '(asdf:make "focus")'
	@if [ -n "$(BUILD_SUFFIX)" ]; then mv build/focus build/focus$(BUILD_SUFFIX); fi

build: clean focus focus-cli

clean:
	rm -rf build

prepare:
	mkdir -p build/static/css build/static/js

frontend: prepare
	cd frontend && lein cljsbuild once min
	cp frontend/resources/public/index.html build/static/
	cp -r frontend/resources/public/img build/static/
	cp frontend/resources/public/css/style.css build/static/css/
	mkdir -p build/static/js
	cp frontend/resources/public/js/app.js build/static/js/
	cp frontend/resources/public/js/lucide.min.js build/static/js/

generate-static: frontend
	sbcl --load tools/build-static.lisp

focus-cli:
	$(SBCL_OPTS) \
	  --eval '(push :binary *features*)' \
	  --eval '(push (merge-pathnames #P"internal-libs/cl-oauth2/" *default-pathname-defaults*) asdf:*central-registry*)' \
	  --eval '(ql:quickload :focus :silent t)' \
	  $(DONTSAVE_FX) \
	  --eval '(ensure-directories-exist "build")' \
	  --eval '(asdf:make "focus-cli")'

dev-start:
	nohup ./build/focus > /tmp/focus.log 2>&1 &

dev-stop:
	-pkill -f ./build/focus

tests:
	sbcl --noinform --non-interactive \
	  --eval '(push (merge-pathnames #P"internal-libs/cl-oauth2/" *default-pathname-defaults*) asdf:*central-registry*)' \
	  --eval '(ql:quickload :focus-tests :silent t)' \
	  --eval '(unless (focus/tests:run-focus-tests) (uiop:quit 1))'

generate-migrations:
	sbcl --load tools/build-migrations.lisp
