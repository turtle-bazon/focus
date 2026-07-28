(in-package :focus)

;;; API Routes

(defun plist-to-json (plist)
  "Convert a plist to a hash-table for JSON encoding."
  (cond
    ((null plist) nil)
    ((typep plist 'local-time:timestamp)
     (princ-to-string plist))
    ((and (listp plist) (keywordp (car plist)))
     (let ((ht (make-hash-table :test 'equal)))
       (iter (for (key val) on plist by #'cddr)
         (setf (gethash (if (keywordp key)
                            (substitute #\_ #\- (string-downcase (symbol-name key)))
                            (format nil "~a" key))
                        ht)
               (plist-to-json val)))
       ht))
    ((and (listp plist) (consp (car plist)))
     (iter (for item in plist) (collecting (plist-to-json item))))
    ((listp plist)
     (iter (for item in plist) (collecting (plist-to-json item))))
    (t plist)))

(defun json-response (data &optional (status 200))
  "Create a JSON response."
  (list status
        '(:content-type "application/json")
        (list (cl-json:encode-json-to-string (plist-to-json data)))))

(defun error-response (message &optional (status 400))
  "Create an error response."
  (json-response `(:error ,message) status))

(defun normalize-json-key (key)
  "Normalize a cl-json keyword key: replace double hyphens with single."
  (let ((name (string key)))
    (iter (with result = (make-array 0 :element-type 'character :adjustable t :fill-pointer 0))
      (for i from 0 below (length name))
      (for ch = (char name i))
      (if (and (char= ch #\-)
               (< (1+ i) (length name))
               (char= (char name (1+ i)) #\-))
          (progn
            (vector-push-extend ch result)
            (incf i))
          (vector-push-extend ch result))
      (finally (return (intern result :keyword))))))

(defun normalize-json-body (alist)
  "Normalize cl-json alist keys to use single hyphens."
  (when alist
    (iter (for (key . val) in alist)
      (collecting (cons (normalize-json-key key) val)))))

(defun json-assoc (key alist)
  "Look up KEY in ALIST using EQUAL test after normalizing both to hyphens."
  (let ((normalized (intern (substitute #\- #\_ (string key)) :keyword)))
    (cdr (assoc normalized alist :test #'equal))))

(defun parse-json-body (env)
  "Parse JSON request body from Clack env."
  (let ((body (getf env :raw-body)))
    (when body
      (let ((content (if (typep body 'stream)
                         (let* ((buf (make-array 4096 :element-type '(unsigned-byte 8) :fill-pointer t))
                                (pos (read-sequence buf body)))
                           (setf (fill-pointer buf) pos)
                           (flexi-streams:octets-to-string buf :external-format :utf-8))
                         (flexi-streams:octets-to-string body :external-format :utf-8))))
        (when (> (length content) 0)
          (normalize-json-body (cl-json:decode-json-from-string content)))))))

(defun parse-query-string (query-string)
  "Parse a URL query string into an alist."
  (when (and query-string (plusp (length query-string)))
    (iter (for pair in (split-sequence:split-sequence #\& query-string))
      (collecting (let ((kv (split-sequence:split-sequence #\= pair)))
                    (cons (car kv) (cadr kv)))))))

(defun get-query-param (query-params name)
  "Get a query parameter by name from parsed query params."
  (cdr (assoc name query-params :test #'string=)))

(defun extract-id-from-path (path regex)
  "Extract numeric ID from path using regex with one capture group."
  (ppcre:register-groups-bind (id)
      (regex path)
    (when id (parse-integer id))))

;;; Activity helpers

(defun get-user-id-from-env (env)
  "Extract user ID from session cookie. Returns integer or NIL."
  (let* ((session-id (cl-oauth2:get-session-id-from-request env))
         (db-session (when session-id (get-db-session session-id))))
    (when db-session
      (getf db-session :user-id))))

(defun log-activity (ticket-id user-id action &key details)
  "Log an activity entry. Silently ignores errors."
  (when user-id
    (handler-case
        (create-activity ticket-id user-id action :details details)
      (error (e)
        (bl:warn "Failed to log activity: ~a" e)))))

;;; Ticket handlers

(defun handle-list-tickets (env)
  "GET /api/tickets"
  (bind ((query-params (parse-query-string (getf env :query-string)))
         (status (get-query-param query-params "status"))
         (priority (get-query-param query-params "priority"))
         (assignee-id (when (get-query-param query-params "assignee_id")
                        (parse-integer (get-query-param query-params "assignee_id"))))
         (page (when (get-query-param query-params "page")
                 (parse-integer (get-query-param query-params "page"))))
         (limit (when (get-query-param query-params "limit")
                  (parse-integer (get-query-param query-params "limit"))))
         (tickets (list-tickets :status status
                                :priority priority
                                :assignee-id assignee-id
                                :page page
                                :limit limit)))
    (json-response `(:tickets ,tickets))))

(defun handle-get-ticket (env)
  "GET /api/tickets/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)$")))
    (if id
        (let ((ticket (get-ticket-by-id id)))
          (if ticket
              (json-response ticket)
              (error-response "Ticket not found" 404)))
        (error-response "Invalid ticket ID"))))

(defun handle-create-ticket (env)
  "POST /api/tickets"
  (bind ((body (parse-json-body env))
         (title (json-assoc :title body))
         (description (json-assoc :description body))
         (status (json-assoc :status body))
         (priority (json-assoc :priority body))
         (assignee-id (json-assoc :assignee_id body)))
    (unless title
      (return-from handle-create-ticket (error-response "Title is required")))
    (bind ((id (create-ticket title
                              :description description
                              :status status
                              :priority priority
                              :assignee-id (when assignee-id
                                            (if (stringp assignee-id)
                                                (parse-integer assignee-id)
                                                assignee-id)))))
      (let ((ticket (get-ticket-by-id id))
            (user-id (get-user-id-from-env env)))
        (log-activity id user-id "created"
                       :details `((:title ,title)))
        (ws-broadcast-ticket-created ticket)
        (json-response `(:id ,id) 201)))))

(defun handle-update-ticket (env)
  "PUT /api/tickets/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)$")))
    (if id
        (bind ((body (parse-json-body env))
               (title (json-assoc :title body))
               (description (json-assoc :description body))
               (status (json-assoc :status body))
               (priority (json-assoc :priority body))
               (assignee-id (json-assoc :assignee_id body))
               (position (json-assoc :position body))
               (old-ticket (get-ticket-by-id id))
               (user-id (get-user-id-from-env env))
               (ticket (if position
                          (reposition-ticket id
                                            (or status "open")
                                            (or priority "medium")
                                            position)
                          (update-ticket id
                                        :title title
                                        :description description
                                        :status status
                                        :priority priority
                                        :assignee-id assignee-id))))
          (if ticket
              (progn
                (when (and old-ticket status (not (equal (getf old-ticket :status) status)))
                  (log-activity id user-id "status_changed"
                                 :details `((:from . ,(getf old-ticket :status)) (:to . ,status))))
                (when (and old-ticket priority (not (equal (getf old-ticket :priority) priority)))
                  (log-activity id user-id "priority_changed"
                                 :details `((:from . ,(getf old-ticket :priority)) (:to . ,priority))))
                (when (and old-ticket title (not (equal (getf old-ticket :title) title)))
                  (log-activity id user-id "title_changed"
                                 :details `((:from . ,(getf old-ticket :title)) (:to . ,title))))
                (ws-broadcast-ticket-update ticket)
                (json-response ticket))
              (error-response "Ticket not found" 404)))
        (error-response "Invalid ticket ID"))))

(defun handle-delete-ticket (env)
  "DELETE /api/tickets/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)$")))
    (if id
        (progn
          (delete-ticket id)
          (ws-broadcast-ticket-deleted id)
          (json-response `(:message "Ticket deleted")))
        (error-response "Invalid ticket ID"))))

;;; Comment handlers

(defun handle-list-comments (env)
  "GET /api/tickets/:id/comments"
  (let ((ticket-id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)/comments$")))
    (if ticket-id
        (json-response `(:comments ,(list-comments ticket-id)))
        (error-response "Invalid ticket ID"))))

(defun handle-create-comment (env)
  "POST /api/tickets/:id/comments"
  (let ((ticket-id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)/comments$")))
    (if ticket-id
        (bind ((body (parse-json-body env))
               (user-id (json-assoc :user_id body))
               (comment-body (json-assoc :body body)))
          (unless user-id
            (return-from handle-create-comment (error-response "User ID is required")))
          (unless comment-body
            (return-from handle-create-comment (error-response "Body is required")))
          (bind ((id (create-comment ticket-id
                                     (if (stringp user-id)
                                         (parse-integer user-id)
                                         user-id)
                                     comment-body))
                 (comment (get-comment-by-id id)))
            (log-activity ticket-id
                          (if (stringp user-id) (parse-integer user-id) user-id)
                          "comment_added"
                          :details `((:user_id ,user-id) (:body ,comment-body)))
            (ws-broadcast-comment-created comment ticket-id)
            (json-response `(:id ,id) 201)))
        (error-response "Invalid ticket ID"))))

;;; Activity handlers

(defun handle-list-activity (env)
  "GET /api/tickets/:id/activity"
  (let ((ticket-id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)/activity$")))
    (if ticket-id
        (json-response `(:activity ,(list-activity ticket-id)))
        (error-response "Invalid ticket ID"))))

;;; Search handlers

(defun handle-search-tickets (env)
  "GET /api/tickets/search?q=..."
  (bind ((query-params (parse-query-string (getf env :query-string)))
         (query (get-query-param query-params "q")))
    (unless query
      (return-from handle-search-tickets (error-response "Query parameter 'q' is required")))
    (bind ((tickets (search-tickets query)))
      (json-response `(:tickets ,tickets)))))

;;; User handlers

(defun handle-list-users (env)
  "GET /api/users"
  (declare (ignore env))
  (json-response `(:users ,(list-users))))

(defun handle-create-user (env)
  "POST /api/users"
  (bind ((body (parse-json-body env))
         (username (json-assoc :username body))
         (email (json-assoc :email body)))
    (unless username
      (return-from handle-create-user (error-response "Username is required")))
    (unless email
      (return-from handle-create-user (error-response "Email is required")))
    (bind ((id (create-user username email)))
      (json-response `(:id ,id) 201))))

;;; Label handlers

(defun handle-list-labels (env)
  "GET /api/labels"
  (declare (ignore env))
  (json-response `(:labels ,(list-labels))))

(defun handle-create-label (env)
  "POST /api/labels"
  (bind ((body (parse-json-body env))
         (name (json-assoc :name body))
         (color (json-assoc :color body)))
    (unless name
      (return-from handle-create-label (error-response "Name is required")))
    (bind ((id (create-label name :color color)))
      (json-response `(:id ,id) 201))))

;;; Attachment handlers

(defun handle-get-attachment (env)
  "GET /api/attachments/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/attachments/(\\d+)$")))
    (if id
        (let ((attachment (get-attachment-by-id id)))
          (if attachment
              (let ((data (get-attachment-data id)))
                (list 200
                      `(("Content-Type" . ,(getf attachment :content_type))
                        ("Content-Disposition" . ,(format nil "attachment; filename=\"~a\"" (getf attachment :filename))))
                      (list data)))
              (error-response "Attachment not found" 404)))
        (error-response "Invalid attachment ID"))))

;;; Webhook handlers

(defun handle-list-webhooks (env)
  "GET /api/webhooks"
  (declare (ignore env))
  (json-response `(:webhooks ,(list-webhooks))))

(defun handle-create-webhook (env)
  "POST /api/webhooks"
  (bind ((body (parse-json-body env))
         (url (json-assoc :url body))
         (secret (json-assoc :secret body))
         (events (json-assoc :events body))
         (active (json-assoc :active body)))
    (unless url
      (return-from handle-create-webhook (error-response "URL is required")))
    (bind ((id (create-webhook url :secret secret :events events :active active)))
      (json-response `(:id ,id) 201))))
