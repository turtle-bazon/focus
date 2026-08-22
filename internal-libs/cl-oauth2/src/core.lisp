(in-package :cl-oauth2)

;;; OAuth2 client configuration

(defclass oauth2-client ()
  ((client-id
    :initarg :client-id
    :accessor client-id
    :type string)
   (client-secret
    :initarg :client-secret
    :accessor client-secret
    :type string)
   (authorize-uri
    :initarg :authorize-uri
    :accessor authorize-uri
    :type string)
   (token-uri
    :initarg :token-uri
    :accessor token-uri
    :type string)
   (redirect-uri
    :initarg :redirect-uri
    :accessor redirect-uri
    :type string)
   (scopes
    :initarg :scopes
    :accessor scopes
    :type list
    :documentation "List of scope strings, e.g. (\"openid\" \"profile\" \"email\")")
   (extra-params
    :initarg :extra-params
    :accessor extra-params
    :initform nil
    :documentation "Extra parameters for authorize request"))
  (:documentation "OAuth2 client configuration"))

(defmethod print-object ((client oauth2-client) stream)
  (print-unreadable-object (client stream :type t)
    (format stream "~a" (client-id client))))

(defun make-oauth2-client (&key client-id client-secret authorize-uri
                                 token-uri redirect-uri
                                 (scopes '("openid"))
                                 (extra-params nil))
  "Create an OAuth2 client."
  (make-instance 'oauth2-client
                 :client-id client-id
                 :client-secret client-secret
                 :authorize-uri authorize-uri
                 :token-uri token-uri
                 :redirect-uri redirect-uri
                 :scopes scopes
                 :extra-params extra-params))

;;; Token type

(defclass oauth2-token ()
  ((access-token
    :initarg :access-token
    :accessor access-token
    :type string)
   (token-type
    :initarg :token-type
    :accessor token-type
    :initform "Bearer"
    :type string)
   (refresh-token
    :initarg :refresh-token
    :accessor refresh-token
    :initform nil)
   (expires-in
    :initarg :expires-in
    :accessor expires-in
    :initform nil)
   (id-token
    :initarg :id-token
    :accessor id-token
    :initform nil
    :documentation "OIDC id_token JWT string")
   (scope
    :initarg :scope
    :accessor token-scope
    :initform nil)
   (obtained-at
    :initarg :obtained-at
    :accessor obtained-at
    :initform (get-universal-time)
    :type integer))
  (:documentation "OAuth2 token response"))

(defun token-expired-p (token)
  "Check if a token has expired."
  (when (expires-in token)
    (> (- (get-universal-time) (obtained-at token))
       (- (expires-in token) 30))))

;;; URL encoding

(defun percent-encode (string)
  "Percent-encode a string for use in URL query parameters."
  (format nil "~{~a~}"
          (map 'list
               (lambda (c)
                 (if (or (alphanumericp c)
                         (find c "-_.~"))
                     (string c)
                     (format nil "%~2,'0x" (char-code c))))
               string)))

(defun url-encode-params (params)
  "Encode an alist of key-value pairs into a query string."
  (format nil "~{~a~^&~}"
          (iter (for (key . val) in params)
            (collecting (format nil "~a=~a"
                                (percent-encode (string-downcase (if (symbolp key) (symbol-name key) key)))
                                (percent-encode (if (stringp val) val (princ-to-string val))))))))

;;; JSON helpers

(defun json-key-symbol (name)
  "Translate a JSON object name to a keyword the way cl-json did:
   underscores become double dashes, e.g. access_token -> :ACCESS--TOKEN."
  (intern (with-output-to-string (out)
            (iter (for c in-string (string name))
                  (if (char= c #\_)
                      (write-string "--" out)
                      (write-char (char-upcase c) out))))
          :keyword))

(defun json-value->lisp (value)
  "Convert a parsed jzon structure into alists with cl-json-style keys."
  (cond ((hash-table-p value)
         (iter (for (key val) in-hashtable value)
           (collecting (cons (json-key-symbol key)
                             (json-value->lisp val)))))
        ;; Strings are vectors in CL — test before the vector branch or
        ;; every string gets shredded into a list of characters.
        ((stringp value) value)
        ((vectorp value)
         (iter (for item in-vector value)
           (collecting (json-value->lisp item))))
        ;; jzon parses JSON null as the symbol NULL (not a keyword).
        ((and (symbolp value) (string-equal (symbol-name value) "NULL"))
         nil)
        (t value)))

(defun parse-json-response (body)
  "Parse a JSON response body into an alist."
  (json-value->lisp (com.inuoe.jzon:parse body)))

(defun json-assoc (key alist)
  "Look up KEY in alist."
  (cdr (assoc key alist :test #'equal)))
