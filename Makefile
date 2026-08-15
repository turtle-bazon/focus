all: build

.PHONY: all build clean prepare frontend dev-start dev-stop tests generate-migrations generate-static

build: clean prepare frontend generate-static
	BUILD_SUFFIX=$(BUILD_SUFFIX) sbcl --non-interactive --load build.lisp

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
