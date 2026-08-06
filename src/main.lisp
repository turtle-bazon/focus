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

(defun app (env)
  "Main app handler — routes to WS or normal handler."
  (if (websocket-driver:websocket-p env)
      (handle-ws-upgrade env)
      (funcall *router* env)))

;;; Server entry point — runs the web app (used as clingon's root handler)

(defun start-server (cmd)
  "Bootstrap the database and run the web server."
  (setf *random-state* (make-random-state t))
  (let ((config (read-config (find-config))))
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
    (when (clingon:getopt cmd :rebuild-db)
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

;;; Entry point

(defun main ()
  (clingon:run (make-root-command)))
