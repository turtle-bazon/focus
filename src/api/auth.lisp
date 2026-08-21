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

;;; OAuth2 / OpenID Connect auth

(defvar *oauth2-client* nil)

(defun authorization-header-from-env (env)
  "Return the Authorization header value from ENV, or nil. Accepts the
   flattened :authorization key and a :headers hash-table/alist with a
   lowercase \"authorization\" entry (Clack/Wookie convention)."
  (or (getf env :authorization)
      (getf (getf env :mode) :authorization)
      (let ((headers (getf env :headers)))
        (when headers
          (if (hash-table-p headers)
              (gethash "authorization" headers)
              (cdr (assoc "authorization" headers :test #'string=)))))))

(defun bearer-token-from-env (env)
  "Extract a bearer token from the Authorization header, or nil."
  (let ((auth (authorization-header-from-env env)))
    (when (and auth (typep auth 'string))
      (let ((trimmed (string/trim auth " ")))
        (when (>= (length trimmed) 7)
          (let ((scheme (subseq trimmed 0 (min 6 (length trimmed)))))
            (when (and (string-equal scheme "Bearer")
                       (> (length trimmed) 7))
              (string/trim (subseq trimmed 7) " "))))))))

(defun make-oauth2-client-from-config (config)
  "Create an OAuth2 client from focus.conf settings."
  (setf *oauth2-client*
        (cl-oauth2:make-oauth2-client
         :client-id (config->oauth2-client-id config)
         :client-secret (config->oauth2-client-secret config)
         :authorize-uri (config->oauth2-authorize-uri config)
         :token-uri (config->oauth2-token-uri config)
         :redirect-uri (config->oauth2-redirect-uri config)
         :scopes (config->oauth2-scopes config))))

(defun generate-state ()
  "Generate a random state parameter for CSRF protection."
  (random-token-hex 16))

(defun generate-session-id ()
  "Generate a random 32-character hex session ID."
  (random-token-hex 16))

;;; Auth handlers

(defun handle-auth-login (env)
  "GET /api/auth/login — redirect to OAuth2 provider."
  (declare (ignore env))
  (unless *oauth2-client*
    (return-from handle-auth-login
      (error-response "OAuth2 not configured" 503)))
  (let ((state (generate-state)))
    (list 302
          `(:location ,(cl-oauth2:authorization-url *oauth2-client* :state state))
          (list ""))))

(defun %handle-auth-error (error-param)
  "Redirect to landing page with error."
  (list 302
        `(:location ,(format nil "/?error=~a" (cl-oauth2:percent-encode error-param)))
        (list "")))

(defun %json-assoc-key (json key)
  "Look up KEY (a string) in a parsed JSON object. Tries the exact key, then
   lowercase and uppercase variants to accommodate provider quirks."
  (when (hash-table-p json)
    (let ((name (string key)))
      (json-normalize
       (or (gethash name json)
           (gethash (string-downcase name) json)
           (gethash (string-upcase name) json))))))

(defun %clean-json-value (val)
  "Normalize JSON null/false/true representations and string \"false\"/\"true\"
   coming from userinfo providers."
  (cond ((eq val 'null) nil)
        ((and (stringp val) (string-equal val "false")) nil)
        ((and (stringp val) (string-equal val "true")) t)
        (t val)))

(defun %derive-picture-url (userinfo-uri user-id)
  "Derive profile picture URL from userinfo URI and user ID.
For Mattermost: /api/v4/users/me → /api/v4/users/{id}/image"
  (when (and userinfo-uri user-id)
    (let ((base (subseq userinfo-uri
                        0
                        (let ((pos (search "/users/me" userinfo-uri)))
                          (if pos pos
                              (let ((pos2 (search "/userinfo" userinfo-uri)))
                                (if pos2 pos2 (length userinfo-uri))))))))
      (format nil "~a/users/~a/image" base user-id))))

(defun %fetch-userinfo (access-tok)
  "Fetch user info from the configured userinfo endpoint.
Returns (values email name username picture) or signals an error."
  (let* ((userinfo-uri (config->oauth2-userinfo-uri *config*))
         (response (dexador:request userinfo-uri
                                   :headers `(("Authorization" . ,(format nil "Bearer ~a" access-tok)))
                                   :force-string t))
         (user-data (jzon:parse response :max-string-length nil))
         (email-key (config->oauth2-userinfo-email-key *config*))
         (username-key (config->oauth2-userinfo-username-key *config*))
         (name-key (config->oauth2-userinfo-name-key *config*))
         (picture-key (config->oauth2-userinfo-picture-key *config*))
         (explicit-picture (%json-assoc-key user-data picture-key))
         (user-id (or (%json-assoc-key user-data "id")
                      (%json-assoc-key user-data "sub")))
         (picture (or explicit-picture (%derive-picture-url userinfo-uri user-id))))
    (bl:info "Userinfo response: ~a" user-data)
    (bl:info "Derived picture URL: ~a" picture)
    (values (%json-assoc-key user-data email-key)
            (%json-assoc-key user-data name-key)
            (%json-assoc-key user-data username-key)
            picture)))

(defun %handle-auth-success (email name username picture)
  "Process successful OAuth2 login."
  (setf email (%clean-json-value email)
        name (%clean-json-value name)
        username (%clean-json-value username))
  (let* ((existing (or (when email (get-user-by-email email))
                       (when username (get-user-by-username username))))
         (deleted-account (and existing (getf existing :is-deleted)))
         (user-id (cond
                    (deleted-account
                     (bl:info "Auth blocked for deleted user: ~a" email)
                     (return-from %handle-auth-success
                       (%handle-auth-error "account-deleted")))
                    (existing
                     (progn (update-user (getf existing :id) :picture picture)
                            (getf existing :id)))
                    (t
                     (create-user (or username name email "user")
                                  (or email (format nil "~a@oauth" (or username "user")))
                                  :picture picture))))
         (session-id (generate-session-id))
         (cookie-header (cl-oauth2:make-set-cookie-header
                         "focus_session" session-id
                         :max-age 86400)))
    (create-db-session session-id user-id
                       (local-time:timestamp+ (local-time:now) 86400 :sec))
    (bl:info "Auth success for ~a, session ~a" email session-id)
    (list 302
          `(:location "/"
            :set-cookie ,cookie-header)
          (list ""))))

(defun handle-auth-callback (env)
  "GET /api/auth/callback — handle OAuth2 callback with auth code."
  (unless *oauth2-client*
    (return-from handle-auth-callback
      (error-response "OAuth2 not configured" 503)))
  (let* ((query-string (getf env :query-string))
         (params (parse-query-string query-string))
         (code (get-query-param params "code"))
         (error-param (get-query-param params "error")))
    (when error-param
      (return-from handle-auth-callback (%handle-auth-error error-param)))
    (unless code
      (return-from handle-auth-callback
        (error-response "Missing authorization code")))
    (handler-case
        (let* ((token (cl-oauth2:exchange-code *oauth2-client* code))
               (access-tok (cl-oauth2:access-token token)))
          (bl:info "Token exchanged, fetching user info")
          (multiple-value-bind (email name username picture) (%fetch-userinfo access-tok)
            (bl:info "email=~a name=~a username=~a" email name username)
            (%handle-auth-success email name username picture)))
      (error (e)
        (bl:error "OAuth2 callback error: ~a" e)
        (%handle-auth-error "auth_failed")))))

(defun handle-auth-me (env)
  "GET /api/auth/me — return current user info."
  (if-let (db-session (when-let (session-id (cl-oauth2:get-session-id-from-request env))
                        (get-db-session session-id)))
      (let* ((user-id (getf db-session :user-id))
             (user (get-user-by-id user-id)))
        (json-response `(:user ,user :authenticated ,t)))
      (json-response `(:authenticated ,nil) 401)))

(defun handle-auth-logout (env)
  "POST /api/auth/logout — clear session."
  (declare (ignore env))
  (let ((session-id (cl-oauth2:get-session-id-from-request env)))
    (when session-id
      (delete-db-session session-id)))
  (list 200
        (list :set-cookie "focus_session=; Path=/; Max-Age=0; HttpOnly")
        (list "{\"message\":\"Logged out\"}")))

(defun handle-app-info (env)
  "GET /api/app/info — return app name, description, version, and OAuth2
  status (public)."
  (declare (ignore env))
  (json-response `(:name ,(config->app-name *config*)
                   :description ,(config->app-description *config*)
                   :version ,(asdf:component-version (asdf:find-system :focus))
                   :oauth2-configured ,(and *oauth2-client*
                                            (plusp (length (cl-oauth2:client-id *oauth2-client*)))))))
