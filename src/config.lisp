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

;;; Config accessors

(defun config->db-host (config) (getf config :db-host))
(defun config->db-port (config) (or (getf config :db-port) 5432))
(defun config->db-name (config) (getf config :db-name))
(defun config->db-user (config) (getf config :db-user))
(defun config->db-pass (config) (getf config :db-pass))
(defun config->bind-address (config) (getf config :bind-address))
(defun config->bind-port (config) (getf config :bind-port))
(defun config->nrepl-port (config) (getf config :nrepl-port))
(defun config->nrepl-address (config) (getf config :nrepl-address))

;;; OAuth2 config

(defun config->oauth2-client-id (config) (getf config :oauth2-client-id))
(defun config->oauth2-client-secret (config) (getf config :oauth2-client-secret))
(defun config->oauth2-authorize-uri (config) (getf config :oauth2-authorize-uri))
(defun config->oauth2-token-uri (config) (getf config :oauth2-token-uri))
(defun config->oauth2-redirect-uri (config) (getf config :oauth2-redirect-uri))
(defun config->oauth2-scopes (config) (or (getf config :oauth2-scopes) '("openid" "profile" "email")))
(defun config->oauth2-userinfo-uri (config) (getf config :oauth2-userinfo-uri))
(defun config->oauth2-userinfo-email-key (config) (or (getf config :oauth2-userinfo-email-key) "email"))
(defun config->oauth2-userinfo-username-key (config) (or (getf config :oauth2-userinfo-username-key) "username"))
(defun config->oauth2-userinfo-name-key (config) (or (getf config :oauth2-userinfo-name-key) "name"))
(defun config->oauth2-userinfo-picture-key (config) (or (getf config :oauth2-userinfo-picture-key) "picture"))
(defun config->app-name (config) (or (getf config :app-name) "Focus"))
(defun config->app-description (config) (or (getf config :app-description) "Issue tracker"))

;;; Config validation

(defun validate-config (config)
  (unless (stringp (config->db-host config))
    (error "db-host must be a string"))
  (unless (stringp (config->db-name config))
    (error "db-name must be a string"))
  (unless (stringp (config->db-user config))
    (error "db-user must be a string"))
  (unless (stringp (config->db-pass config))
    (error "db-pass must be a string"))
  (unless (or (null (config->bind-address config))
              (stringp (config->bind-address config)))
    (error "bind-address must be nil or string"))
  (unless (and (integerp (config->bind-port config))
               (> (config->bind-port config) 0)
               (<= (config->bind-port config) 65535))
    (error "bind-port must be integer 1-65535"))
  t)

;;; Config discovery

(defun find-config ()
  (or (probe-file "focus.conf")
      (probe-file (merge-pathnames #P".focus.conf" (user-homedir-pathname)))
      (probe-file (merge-pathnames #P".config/focus/focus.conf" (user-homedir-pathname)))
      (probe-file "/etc/focus.conf")))

(defun read-config (file)
  (bind ((probed (and file (probe-file file))))
    (unless (and probed (pathname-name probed))
      (error "Configuration file doesn't exist or is not readable: ~a" file))
    (handler-case
        (bind ((config (with-open-file (stream file)
                         (read stream))))
          (validate-config config)
          config)
      (error ()
        (error "Error while reading configuration: ~a" file)))))
