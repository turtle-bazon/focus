(in-package :cl-oauth2)

;;; OAuth2 flows

(defun authorization-url (client &key state nonce)
  "Build the authorization URL for the authorization code flow.
Returns a URL string to redirect the user to."
  (let ((params `((:client_id . ,(client-id client))
                  (:redirect_uri . ,(redirect-uri client))
                  (:response_type . "code")
                  (:scope . ,(format nil "~{~a~^ ~}" (scopes client)))
                  ,@(when state `((:state . ,state)))
                  ,@(when nonce `((:nonce . ,nonce)))
                  ,@(extra-params client))))
    (format nil "~a?~a" (authorize-uri client) (url-encode-params params))))

(defun exchange-code (client code &key state)
  "Exchange an authorization code for tokens.
Returns an OAuth2-TOKEN instance."
  (let* ((params `((:grant_type . "authorization_code")
                   (:code . ,code)
                   (:redirect_uri . ,(redirect-uri client))
                   (:client_id . ,(client-id client))
                   (:client_secret . ,(client-secret client))
                   ,@(when state `((:state . ,state)))))
         (body (url-encode-params params))
         (response (dexador:request (token-uri client)
                                   :method :post
                                   :content body
                                   :headers '(("Content-Type" . "application/x-www-form-urlencoded"))
                                   :force-string t)))
    (let ((data (parse-json-response response)))
      (make-instance 'oauth2-token
                     :access-token (or (json-assoc :access--token data)
                                       (json-assoc :access_token data))
                     :token-type (or (json-assoc :token--type data)
                                     (json-assoc :token_type data)
                                     "Bearer")
                     :refresh-token (or (json-assoc :refresh--token data)
                                        (json-assoc :refresh_token data))
                     :expires-in (json-assoc :expires--in data)
                     :id-token (or (json-assoc :id--token data)
                                   (json-assoc :id_token data))
                     :scope (or (json-assoc :scope data) nil)))))

(defun refresh-access-token (client token)
  "Refresh an expired access token. Returns a new OAuth2-TOKEN."
  (unless (refresh-token token)
    (error "No refresh token available"))
  (let* ((params `((:grant_type . "refresh_token")
                   (:refresh_token . ,(refresh-token token))
                   (:client_id . ,(client-id client))
                   (:client_secret . ,(client-secret client))))
         (body (url-encode-params params))
         (response (dexador:request (token-uri client)
                                   :method :post
                                   :content body
                                   :headers '(("Content-Type" . "application/x-www-form-urlencoded"))
                                   :force-string t)))
    (let ((data (parse-json-response response)))
      (make-instance 'oauth2-token
                     :access-token (or (json-assoc :access--token data)
                                       (json-assoc :access_token data))
                     :token-type (or (json-assoc :token--type data)
                                     (json-assoc :token_type data)
                                     "Bearer")
                     :refresh-token (or (json-assoc :refresh--token data)
                                        (json-assoc :refresh_token data)
                                        (refresh-token token))
                     :expires-in (json-assoc :expires--in data)
                     :id-token (or (json-assoc :id--token data)
                                   (json-assoc :id_token data)
                                   (id-token token))
                     :scope (or (json-assoc :scope data) (token-scope token))))))

(defun fetch-userinfo (client token)
  "Fetch user info from the OIDC userinfo endpoint.
Returns an alist of claims."
  (let* ((url (format nil "~a/userinfo" (authorization-base client)))
         (response (dexador:request url
                                   :method :get
                                   :headers `(("Authorization" . ,(format nil "~a ~a"
                                                                          (token-type token)
                                                                          (access-token token))))
                                   :force-string t)))
    (parse-json-response response)))

(defun authorization-base (client)
  "Extract the base URL from the authorize URI (everything before /oauth or /authorize)."
  (let ((uri (authorize-uri client)))
    (ppcre:register-groups-bind (base)
        ("^(https?://[^/]+)" uri)
      base)))
