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

;;; Issue handlers

(defun handle-list-issues (env)
  "GET /api/issues"
  (bind ((query-params (parse-query-string (getf env :query-string)))
         (status (get-query-param query-params "status"))
         (priority (get-query-param query-params "priority"))
         (assignee-id (when (get-query-param query-params "assignee_id")
                        (parse-integer (get-query-param query-params "assignee_id"))))
         (page (when (get-query-param query-params "page")
                 (parse-integer (get-query-param query-params "page"))))
         (limit (when (get-query-param query-params "limit")
                  (parse-integer (get-query-param query-params "limit"))))
         (issues (list-issues :status status
                              :priority priority
                              :assignee-id assignee-id
                              :page page
                              :limit limit)))
    (json-response `(:issues ,issues))))

(defun handle-get-issue (env)
  "GET /api/issues/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/issues/(\\d+)$")))
    (if id
        (let ((issue (get-issue-by-id id)))
          (if issue
              (json-response issue)
              (error-response "Issue not found" 404)))
        (error-response "Invalid issue ID"))))

(defun handle-create-issue (env)
  "POST /api/issues"
  (bind ((body (parse-json-body env))
         (title (json-assoc :title body))
         (description (json-assoc :description body))
         (status (json-assoc :status body))
         (priority (json-assoc :priority body))
         (assignee-id (json-assoc :assignee_id body)))
    (unless title
      (return-from handle-create-issue (error-response "Title is required")))
    (bind ((id (create-issue title
                            :description description
                            :status status
                            :priority priority
                            :assignee-id (when assignee-id
                                          (if (stringp assignee-id)
                                              (parse-integer assignee-id)
                                              assignee-id)))))
      (let ((issue (get-issue-by-id id)))
        (ws-broadcast-issue-created issue)
        (json-response `(:id ,id) 201)))))

(defun handle-update-issue (env)
  "PUT /api/issues/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/issues/(\\d+)$")))
    (if id
        (bind ((body (parse-json-body env))
               (title (json-assoc :title body))
               (description (json-assoc :description body))
               (status (json-assoc :status body))
               (priority (json-assoc :priority body))
               (assignee-id (json-assoc :assignee_id body))
               (position (json-assoc :position body))
               (issue (if position
                         (reposition-issue id
                                          (or status "open")
                                          (or priority "medium")
                                          position)
                         (update-issue id
                                      :title title
                                      :description description
                                      :status status
                                      :priority priority
                                      :assignee-id assignee-id))))
          (if issue
              (progn
                (ws-broadcast-issue-update issue)
                (json-response issue))
              (error-response "Issue not found" 404)))
        (error-response "Invalid issue ID"))))

(defun handle-delete-issue (env)
  "DELETE /api/issues/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/issues/(\\d+)$")))
    (if id
        (progn
          (delete-issue id)
          (ws-broadcast-issue-deleted id)
          (json-response `(:message "Issue deleted")))
        (error-response "Invalid issue ID"))))

;;; Comment handlers

(defun handle-list-comments (env)
  "GET /api/issues/:id/comments"
  (let ((issue-id (extract-id-from-path (getf env :path-info) "^/api/issues/(\\d+)/comments$")))
    (if issue-id
        (json-response `(:comments ,(list-comments issue-id)))
        (error-response "Invalid issue ID"))))

(defun handle-create-comment (env)
  "POST /api/issues/:id/comments"
  (let ((issue-id (extract-id-from-path (getf env :path-info) "^/api/issues/(\\d+)/comments$")))
    (if issue-id
        (bind ((body (parse-json-body env))
               (user-id (json-assoc :user_id body))
               (comment-body (json-assoc :body body)))
          (unless user-id
            (return-from handle-create-comment (error-response "User ID is required")))
          (unless comment-body
            (return-from handle-create-comment (error-response "Body is required")))
          (bind ((id (create-comment issue-id
                                     (if (stringp user-id)
                                         (parse-integer user-id)
                                         user-id)
                                     comment-body))
                 (comment (get-comment-by-id id)))
            (ws-broadcast-comment-created comment issue-id)
            (json-response `(:id ,id) 201)))
        (error-response "Invalid issue ID"))))

;;; Activity handlers

(defun handle-list-activity (env)
  "GET /api/issues/:id/activity"
  (let ((issue-id (extract-id-from-path (getf env :path-info) "^/api/issues/(\\d+)/activity$")))
    (if issue-id
        (json-response `(:activity ,(list-activity issue-id)))
        (error-response "Invalid issue ID"))))

;;; Search handlers

(defun handle-search-issues (env)
  "GET /api/issues/search?q=..."
  (bind ((query-params (parse-query-string (getf env :query-string)))
         (query (get-query-param query-params "q")))
    (unless query
      (return-from handle-search-issues (error-response "Query parameter 'q' is required")))
    (bind ((issues (search-issues query)))
      (json-response `(:issues ,issues)))))

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
