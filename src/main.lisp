;;; focus — ticket tracker
;;; Copyright (C) 2026 Azamat S. Kalimoulline <turtle@bazon.ru>
;;;
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with this program.  If not, see <https://www.gnu.org/licenses/>.
;;;

(in-package :focus)

;;; App handler — trampoline for hot reload

(defvar *router* nil)
(defvar *config* nil)

(defun reload-foreign-libraries (&key skip-libraries required-symbols)
  "Refresh CFFI foreign libraries against the running host. Binaries are
   dumped with shared objects marked dont-save, so nothing is reopened at
   startup by build-host soname (libcrypto.so.1.1 vs .so.3); here we drop
   the stale handles and load every registered library through its own
   candidate list, matching whatever the target machine has.
   SKIP-LIBRARIES lists base names (e.g. \"LIBUV\") the caller never uses;
   REQUIRED-SYMBOLS are checked after loading, warning loudly if missing."
  (dolist (lib (cffi:list-foreign-libraries))
    (ignore-errors (cffi:close-foreign-library lib)))
  (flet ((base-name (name)
           (if (symbolp name) (symbol-name name) (princ-to-string name))))
    (dolist (lib (cffi:list-foreign-libraries :loaded-only nil))
      (let ((name (cffi:foreign-library-name lib)))
        (unless (member (base-name name) skip-libraries :test #'string-equal)
          (handler-case (cffi:load-foreign-library name)
            (error (e)
              (bl:warn "Failed to load foreign library ~s: ~a" name e)))))))
  ;; Belt and braces: if the build host's cl+ssl predates OpenSSL 3, its
  ;; candidate lists may not include the target's sonames. Load the usual
  ;; ones directly — whichever succeeds makes the symbols globally visible.
  (dolist (name '("libcrypto.so.3" "libcrypto.so.1.1" "libcrypto.so"
                  "libssl.so.3" "libssl.so.1.1" "libssl.so"
                  "libuv.so.1" "libuv.so"))
    (ignore-errors (cffi:load-foreign-library name)))
  ;; Fail loudly if something critical did not come back.
  (dolist (symbol (or required-symbols '("SSL_new" "uv_loop_init")))
    (unless (cffi:foreign-symbol-pointer symbol)
      (bl:warn "Foreign symbol ~a is unresolved after library reload —
 the feature depending on it will fail" symbol))))

(defun app (env)
  "Main app handler — routes to WS or normal handler."
  (if (websocket-driver:websocket-p env)
      (handle-ws-upgrade env)
      (funcall *router* env)))

;;; Server entry point — runs the web app (used as clingon's root handler)

(defun bootstrap-database (config cmd)
  "Connect, run migrations, initialize OAuth2; honor --rebuild-db."
  (connect-db config)
  (setf local-time:*default-timezone* local-time:+utc-zone+)
  (local-time:set-local-time-cl-postgres-readers)
  (migrate-up)
  (make-oauth2-client-from-config config)
  (when (clingon:getopt cmd :rebuild-db)
    (bl:info "Rebuilding database...")
    (migrate-down)
    (migrate-up)))

(defun start-nrepl-if-configured (config)
  "Start the line-based nREPL when :nrepl-port is set."
  (let ((nrepl-port (config->nrepl-port config)))
    (when nrepl-port
      (start-nrepl nrepl-port
                   :interface (or (config->nrepl-address config) "127.0.0.1")))))

(defun start-web-server (config)
  "Run the Clack server on the configured address and port."
  (let ((bind-addr (or (config->bind-address config) "0.0.0.0"))
        (port (config->bind-port config)))
    (bl:info "Listening on ~a:~a" bind-addr port)
    (clack:clackup #'app
                    :address bind-addr
                    :port port
                    :server :wookie
                    :use-thread nil
                    :debug nil)))

(defun start-server (cmd)
  "Bootstrap the database and run the web server."
  (setf *random-state* (make-random-state t))
  (let ((args (clingon:command-arguments cmd)))
    (when args
      (format t "Unknown command: ~{~a~^ ~}~%" args)
      (clingon:print-usage cmd t)
      (uiop:quit 1)))
  (let ((config (read-config (find-config))))
    (setf *config* config)
    ;; Configure logging
    (bl:configure-log-level :info)
    ;; bazon-log captures *standard-output*'s value at load time; in a
    ;; dumped binary that is the build process's stdout. Re-anchor.
    (bl:configure-log-path nil)
    (bl:info "focus starting...")
    ;; Re-open foreign libraries against THIS host before anything uses them
    (reload-foreign-libraries)
    ;; Set router trampoline
    (setf *router* (function router))
    ;; Connect DB, migrate, OAuth2, optional rebuild
    (bootstrap-database config cmd)
    (start-nrepl-if-configured config)
    (start-web-server config)))

;;; Entry point

(defun main ()
  (clingon:run (make-root-command)))
