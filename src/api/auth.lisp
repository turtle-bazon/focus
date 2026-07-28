(in-package :focus)

;;; OAuth2 / OpenID Connect auth

(defvar *session-store* (cl-oauth2:make-session-store :ttl 86400))
(defvar *oauth2-client* nil)

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
  (let ((bytes (make-array 16 :element-type '(unsigned-byte 8))))
    (iter (for i from 0 below 16)
      (setf (aref bytes i) (random 256)))
    (format nil "~{~2,'0x~}" (coerce bytes 'list))))

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

(defun %handle-auth-success (email name username)
  "Process successful OAuth2 login."
  (let* ((user (or (when email (get-user-by-email email))
                   (create-user (or username name email "user") (or email (format nil "~a@mattermost" (or username "user"))))))
         (session-id (cl-oauth2:create-session *session-store* user))
         (cookie-header (cl-oauth2:make-set-cookie-header
                         "focus_session" session-id
                         :max-age 86400)))
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
          (bl:info "Token exchanged, fetching user info from Mattermost")
          (let* ((user-url (format nil "~a/api/v4/users/me" (cl-oauth2:authorization-base *oauth2-client*)))
                 (response (dexador:request user-url
                                           :headers `(("Authorization" . ,(format nil "Bearer ~a" access-tok)))
                                           :force-string t))
                 (user-data (cl-json:decode-json-from-string response)))
            (bl:info "Mattermost user: ~a" user-data)
            (let ((email (cdr (assoc :email user-data)))
                  (name (cdr (assoc :first--name user-data)))
                  (username (cdr (assoc :username user-data))))
              (bl:info "email=~a name=~a username=~a" email name username)
              (%handle-auth-success email name username))))
      (error (e)
        (bl:error "OAuth2 callback error: ~a" e)
        (%handle-auth-error "auth_failed")))))

(defun handle-auth-me (env)
  "GET /api/auth/me — return current user info."
  (let* ((headers (getf env :headers))
         (cookie-str (when (hash-table-p headers) (gethash "cookie" headers)))
         (_ (bl:info "Raw cookie: ~a" cookie-str))
         (session-id (cl-oauth2:get-session-id-from-request env))
         (_ (bl:info "Session ID: ~a" session-id))
         (session (cl-oauth2:get-session *session-store* session-id)))
    (bl:info "Session found: ~a" (if session t nil))
    (if session
        (let ((user (cl-oauth2:session-user session)))
          (json-response `(:user ,user :authenticated ,t)))
        (json-response `(:authenticated ,nil) 401))))

(defun handle-auth-logout (env)
  "POST /api/auth/logout — clear session."
  (declare (ignore env))
  (let ((session-id (cl-oauth2:get-session-id-from-request env)))
    (when session-id
      (cl-oauth2:delete-session *session-store* session-id)))
  (list 200
        (list (cl-oauth2:clear-session-cookie))
        (list "{\"message\":\"Logged out\"}")))

(defun handle-app-info (env)
  "GET /api/app/info — return app name and description (public)."
  (declare (ignore env))
  (json-response `(:name ,(config->app-name *config*)
                   :description ,(config->app-description *config*)
                   :oauth2-configured ,(and *oauth2-client*
                                            (plusp (length (cl-oauth2:client-id *oauth2-client*)))))))
