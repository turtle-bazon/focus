(in-package :focus)

;;; App handler — trampoline for hot reload

(defvar *router* nil)
(defvar *config* nil)

(defun app (env)
  "Main app handler — routes to WS or normal handler."
  (if (websocket-driver:websocket-p env)
      (handle-ws-upgrade env)
      (funcall *router* env)))

;;; CLI argument parsing

(defun parse-args (args)
  "Parse command line arguments."
  (let ((result nil)
        (rest (cdr args)))
    (do () ((null rest))
      (let ((key (car rest)))
        (setf rest (cddr rest))
        (when (string= key "--rebuild-db")
          (setf (getf result :rebuild-db) t))))
    result))

;;; Entry point

(defun main (&rest args)
  (setf *random-state* (make-random-state t))
  (let ((config (read-config (find-config)))
        (cli-opts (parse-args args)))
    (setf *config* config)
    ;; Configure logging
    (bl:configure-log-level :info)
    (bl:info "focus starting...")
    ;; Set router trampoline
    (setf *router* (function router))
    ;; Connect DB and run migrations
    (connect-db config)
    (setf local-time:*default-timezone* local-time:+utc-zone+)
    (local-time:set-local-time-cl-postgres-readers)
    (migrate-up)
    ;; Initialize OAuth2 client from config
    (make-oauth2-client-from-config config)
    ;; Check --rebuild-db flag
    (when (getf cli-opts :rebuild-db)
      (bl:info "Rebuilding database...")
      (migrate-down)
      (migrate-up))
    ;; Start nREPL
    (let ((nrepl-port (config->nrepl-port config)))
      (when nrepl-port
        (start-nrepl nrepl-port
                     :interface (or (config->nrepl-address config) "127.0.0.1"))))
    ;; Start web server
    (let ((bind-addr (or (config->bind-address config) "0.0.0.0"))
          (port (config->bind-port config)))
      (bl:info "Listening on ~a:~a" bind-addr port)
      (clack:clackup #'app
                      :address bind-addr
                      :port port
                      :server :wookie
                      :use-thread nil
                      :debug nil))))
