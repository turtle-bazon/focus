(in-package :cl-oauth2)

;;; In-memory session store with cookie support

(defstruct session
  id
  user
  token
  (created-at (get-universal-time) :type integer)
  (expires-at nil))

(defclass session-store ()
  ((sessions
    :initarg :sessions
    :accessor sessions
    :initform (make-hash-table :test 'equal)
    :documentation "Map session-id -> session struct")
   (ttl
    :initarg :ttl
    :accessor session-ttl
    :initform 86400
    :documentation "Session time-to-live in seconds (default: 24 hours)")
   (lock
    :initarg :lock
    :accessor session-lock
    :initform (bt:make-lock "session-store")))
  (:documentation "Thread-safe in-memory session store"))

(defun make-session-store (&key (ttl 86400))
  "Create a session store with given TTL in seconds."
  (make-instance 'session-store :ttl ttl))

(defun generate-session-id ()
  "Generate a random 32-character hex session ID."
  (let ((bytes (make-array 16 :element-type '(unsigned-byte 8))))
    (iter (for i from 0 below 16)
      (setf (aref bytes i) (random 256)))
    (format nil "~{~2,'0x~}" (coerce bytes 'list))))

(defun create-session (store user &key token)
  "Create a new session for a user. Returns the session ID."
  (let ((id (generate-session-id))
        (now (get-universal-time)))
    (bt:with-lock-held ((session-lock store))
      (setf (gethash id (sessions store))
            (make-session :id id
                          :user user
                          :token token
                          :created-at now
                          :expires-at (+ now (session-ttl store)))))
    id))

(defun get-session (store session-id)
  "Retrieve a session by ID. Returns nil if expired or not found."
  (when session-id
    (bt:with-lock-held ((session-lock store))
      (let ((session (gethash session-id (sessions store))))
        (when session
          (if (and (session-expires-at session)
                   (> (get-universal-time) (session-expires-at session)))
              (progn
                (remhash session-id (sessions store))
                nil)
              session))))))

(defun delete-session (store session-id)
  "Delete a session by ID."
  (bt:with-lock-held ((session-lock store))
    (remhash session-id (sessions store))))

(defun session-store-purge-expired (store)
  "Remove all expired sessions. Returns count of removed sessions."
  (let ((now (get-universal-time))
        (removed 0))
    (bt:with-lock-held ((session-lock store))
      (iter (for (id session) in-hashtable (sessions store))
        (when (and (session-expires-at session)
                   (> now (session-expires-at session)))
          (remhash id (sessions store))
          (incf removed))))
    removed))

;;; Cookie helpers

(defun parse-cookies (cookie-header)
  "Parse a Cookie header string into an alist."
  (when (and cookie-header (plusp (length cookie-header)))
    (iter (for pair in (split-sequence:split-sequence #\; cookie-header))
      (let ((kv (split-sequence:split-sequence #\= (string-trim " " pair))))
        (when (= (length kv) 2)
          (collecting (cons (string-trim " " (car kv))
                            (string-trim " " (cadr kv)))))))))

(defun get-cookie (headers name)
  "Get a cookie value by name. Headers can be alist or hash-table."
  (let ((cookie-val (if (hash-table-p headers)
                        (gethash "cookie" headers)
                        (cdr (assoc "cookie" headers :test #'string=)))))
    (cdr (assoc name (parse-cookies cookie-val) :test #'string=))))

(defun make-set-cookie-header (name value &key (max-age 86400) (path "/") (httponly t) (secure nil))
  "Generate a Set-Cookie header value."
  (format nil "~a=~a; Path=~a; Max-Age=~a~a~a"
          name value path max-age
          (if httponly "; HttpOnly" "")
          (if secure "; Secure" "")))

(defun set-session-cookie (session-id &key (max-age 86400))
  "Generate a Set-Cookie header pair for the session cookie."
  (cons "Set-Cookie" (make-set-cookie-header "focus_session" session-id
                                             :max-age max-age)))

(defun get-session-id-from-request (env)
  "Extract session ID from the request Cookie header."
  (let ((headers (getf env :headers)))
    (when headers
      (get-cookie headers "focus_session"))))

(defun clear-session-cookie ()
  "Generate a Set-Cookie header that clears the session cookie."
  (cons "Set-Cookie" "focus_session=; Path=/; Max-Age=0; HttpOnly"))
