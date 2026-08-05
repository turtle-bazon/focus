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

(defun as-int (value)
  "Coerce a JSON value to an integer. cl-json decodes numbers as integers,
   but other callers may pass strings."
  (cond ((integerp value) value)
        ((stringp value) (parse-integer value))
        (t nil)))

(defun json-id-list (value)
  "Coerce a JSON array of IDs into a list of integers.
   Accepts vectors, lists, or nil. Non-numeric entries are skipped."
  (when value
    (iter (for item in-sequence value)
      (for id = (cond ((integerp item) item)
                      ((and (stringp item) (every #'digit-char-p item))
                       (parse-integer item))))
      (when id (collecting id)))))

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
         (board-id (when (get-query-param query-params "board_id")
                     (parse-integer (get-query-param query-params "board_id"))))
         (page (when (get-query-param query-params "page")
                 (parse-integer (get-query-param query-params "page"))))
         (limit (when (get-query-param query-params "limit")
                  (parse-integer (get-query-param query-params "limit"))))
         (tickets (list-tickets :status status
                                :priority priority
                                :assignee-id assignee-id
                                :board-id board-id
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
         (assignee-id (json-assoc :assignee_id body))
         (assignee-type (json-assoc :assignee_type body))
         (color (json-assoc :color body))
         (board-id (json-assoc :board_id body)))
    (unless title
      (return-from handle-create-ticket (error-response "Title is required")))
    (bind ((id (create-ticket title
                              :description description
                              :status status
                              :priority priority
                              :assignee-id (when assignee-id
                                            (if (stringp assignee-id)
                                                (parse-integer assignee-id)
                                                assignee-id))
                              :assignee-type assignee-type
                              :color color
                              :board-id (when board-id
                                         (if (stringp board-id)
                                             (parse-integer board-id)
                                             board-id)))))
      (let ((ticket (get-ticket-by-id id))
            (user-id (get-user-id-from-env env)))
        (when (and ticket assignee-id)
          (ensure-board-member (getf ticket :board-id)
                               (or assignee-type "user")
                               (if (stringp assignee-id)
                                   (parse-integer assignee-id)
                                   assignee-id)))
        (log-activity id user-id "created"
                       :details `((:title . ,title)))
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
               (assignee-type (json-assoc :assignee_type body))
               (color (json-assoc :color body))
               (position (json-assoc :position body))
               (board-id (json-assoc :board_id body))
               (old-ticket (get-ticket-by-id id))
               (user-id (get-user-id-from-env env))
               (new-board (if board-id
                              (if (stringp board-id)
                                  (parse-integer board-id)
                                  board-id)
                              (getf old-ticket :board-id))))
          (unless old-ticket
            (return-from handle-update-ticket (error-response "Ticket not found" 404)))
          ;; Enforce lifecycle transitions.
          ;; When the destination board is unchanged, every status move must be allowed.
          (when (and status
                     (not (equal status (getf old-ticket :status))))
            (if (equal new-board (getf old-ticket :board-id))
                (unless (transition-allowed-p new-board (getf old-ticket :status) status)
                  (return-from handle-update-ticket
                    (error-response "Status transition is not allowed by this board's workflow")))
                (let ((codes (mapcar (lambda (s) (getf s :code)) (list-board-statuses new-board))))
                  (unless (member status codes :test #'string=)
                    (setf status (car codes))))))
          (bind ((ticket (if position
                              (reposition-ticket id
                                                 (or status (getf old-ticket :status))
                                                 (or priority "medium")
                                                 position)
                              (update-ticket id
                                            :title title
                                            :description description
                                            :status status
                                            :priority priority
                                            :assignee-id assignee-id
                                            :assignee-type assignee-type
                                            :color color
                                            :board-id (when board-id new-board)))))
          (when (and ticket (not (equal new-board (getf old-ticket :board-id))))
            ;; Moving to another board: re-ensure assignee and observers belong to it.
            (when (getf ticket :assignee-id)
              (ensure-board-member new-board
                                   (or (getf ticket :assignee-type) "user")
                                   (getf ticket :assignee-id)))
            (iter (for obs in (list-ticket-observers id))
              (ensure-board-member new-board
                                   (getf obs :observer_type)
                                   (getf obs :observer_id))))
          (when (and ticket assignee-id)
            ;; New/changed assignee automatically joins the board.
            (let ((parsed (if (stringp assignee-id) (parse-integer assignee-id) assignee-id)))
              (ensure-board-member (getf ticket :board-id)
                                   (or assignee-type "user")
                                   parsed)))
          (if ticket
              (progn
                (let ((status-changed (and old-ticket status (not (equal (getf old-ticket :status) status))))
                      (priority-changed (and old-ticket priority (not (equal (getf old-ticket :priority) priority))))
                      (title-changed (and old-ticket title (not (equal (getf old-ticket :title) title)))))
                  (when (and status-changed priority-changed)
                    (log-activity id user-id "status_priority_changed"
                                  :details `(("old-status" . ,(getf old-ticket :status))
                                             ("new-status" . ,status)
                                             ("old-priority" . ,(getf old-ticket :priority))
                                             ("new-priority" . ,priority))))
                  (when (and status-changed (not priority-changed))
                    (log-activity id user-id "status_changed"
                                  :details `((:from . ,(getf old-ticket :status)) (:to . ,status))))
                  (when (and priority-changed (not status-changed))
                    (log-activity id user-id "priority_changed"
                                  :details `((:from . ,(getf old-ticket :priority)) (:to . ,priority))))
                  (when title-changed
                    (log-activity id user-id "title_changed"
                                  :details `((:from . ,(getf old-ticket :title)) (:to . ,title)))))
                ;; Any edit makes the editor an observer of the ticket.
                (when (and user-id (get-user-by-id user-id))
                  (add-ticket-observer id "user" user-id))
                (ws-broadcast-ticket-update ticket)
                (json-response ticket))
              (error-response "Ticket not found" 404))))
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
        (let* ((query (getf env :query-string))
               (params (parse-query-string query))
               (limit-str (cdr (assoc "limit" params :test #'string=)))
               (offset-str (cdr (assoc "offset" params :test #'string=)))
               (limit (if limit-str (parse-integer limit-str) 50))
               (offset (if offset-str (parse-integer offset-str) 0))
               (comments (list-comments ticket-id :limit limit :offset offset))
               (total (count-comments ticket-id)))
          (json-response `(:comments ,comments :total ,total)))
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
                          :details `((:user_id . ,user-id) (:body . ,comment-body)))
            ;; Commenting makes the commenter an observer of the ticket.
            (add-ticket-observer ticket-id
                                 "user"
                                 (if (stringp user-id) (parse-integer user-id) user-id))
            (ws-broadcast-comment-created comment ticket-id)
            (json-response `(:id ,id) 201)))
        (error-response "Invalid ticket ID"))))

;;; Activity handlers

(defun handle-list-activity (env)
  "GET /api/tickets/:id/activity"
  (let ((ticket-id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)/activity$")))
    (if ticket-id
        (let* ((query (getf env :query-string))
               (params (parse-query-string query))
               (limit-str (cdr (assoc "limit" params :test #'string=)))
               (offset-str (cdr (assoc "offset" params :test #'string=)))
               (limit (if limit-str (parse-integer limit-str) 20))
               (offset (if offset-str (parse-integer offset-str) 0))
               (activity (list-activity ticket-id :limit limit :offset offset))
               (total (count-activity ticket-id)))
          (json-response `(:activity ,activity :total ,total)))
        (error-response "Invalid ticket ID"))))

(defun handle-list-board-activity (env)
  "GET /api/boards/:id/activity"
  (let ((board-id (extract-id-from-path (getf env :path-info)
                                        "^/api/boards/(\\d+)/activity$")))
    (if board-id
        (let ((forbidden (board-visibility-response env)))
          (if forbidden
              forbidden
              (let* ((query (getf env :query-string))
                     (params (parse-query-string query))
                     (limit-str (cdr (assoc "limit" params :test #'string=)))
                     (offset-str (cdr (assoc "offset" params :test #'string=)))
                     (limit (if limit-str (parse-integer limit-str) 20))
                     (offset (if offset-str (parse-integer offset-str) 0))
                     (activity (list-board-activity board-id :limit limit :offset offset))
                     (total (count-board-activity board-id)))
                (json-response `(:activity ,activity :total ,total)))))
        (error-response "Invalid board ID"))))

(defun handle-list-all-board-activity (env)
  "GET /api/activity — combined activity across all visible boards."
  (let* ((query (getf env :query-string))
         (params (parse-query-string query))
         (limit-str (cdr (assoc "limit" params :test #'string=)))
         (offset-str (cdr (assoc "offset" params :test #'string=)))
         (limit (if limit-str (parse-integer limit-str) 20))
         (offset (if offset-str (parse-integer offset-str) 0))
         (user-id (get-user-id-from-env env))
         (activity (list-all-board-activity user-id :limit limit :offset offset))
         (total (count-all-board-activity user-id)))
    (json-response `(:activity ,activity :total ,total))))

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

(defun handle-update-user (env)
  "PUT /api/users/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/users/(\\d+)$")))
    (if id
        (bind ((body (parse-json-body env))
               (username (json-assoc :username body))
               (email (json-assoc :email body))
               (role (json-assoc :role body)))
          (json-response (apply #'update-user id
                                (append (when username (list :username username))
                                        (when email (list :email email))
                                        (when role (list :role role))))))
        (error-response "Invalid user ID"))))

(defun handle-delete-user (env)
  "DELETE /api/users/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/users/(\\d+)$")))
    (if id
        (progn (delete-user id)
               (json-response `(:message "User deleted")))
        (error-response "Invalid user ID"))))

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

;;; Group handlers

(defun handle-list-groups (env)
  "GET /api/groups"
  (declare (ignore env))
  (json-response `(:groups ,(list-groups))))

(defun handle-create-group (env)
  "POST /api/groups"
  (bind ((body (parse-json-body env))
         (name (json-assoc :name body)))
    (unless name
      (return-from handle-create-group (error-response "Name is required")))
    (bind ((id (create-group name)))
      (json-response `(:id ,id) 201))))

(defun handle-get-group (env)
  "GET /api/groups/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/groups/(\\d+)$")))
    (if id
        (let ((group (get-group-by-id id)))
          (if group
              (json-response group)
              (error-response "Group not found" 404)))
        (error-response "Invalid group ID"))))

(defun handle-update-group (env)
  "PUT /api/groups/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/groups/(\\d+)$")))
    (if id
        (bind ((body (parse-json-body env))
               (name (json-assoc :name body)))
          (update-group id :name name)
          (json-response (get-group-by-id id)))
        (error-response "Invalid group ID"))))

(defun handle-delete-group (env)
  "DELETE /api/groups/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/groups/(\\d+)$")))
    (if id
        (progn
          (delete-group id)
          (json-response `(:message "Group deleted")))
        (error-response "Invalid group ID"))))

(defun handle-list-group-members (env)
  "GET /api/groups/:id/members"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/groups/(\\d+)/members$")))
    (if id
        (json-response `(:members ,(list-group-members id)))
        (error-response "Invalid group ID"))))

(defun handle-add-group-member (env)
  "POST /api/groups/:id/members"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/groups/(\\d+)/members$")))
    (if id
        (bind ((body (parse-json-body env))
               (user-id (json-assoc :user_id body)))
          (unless user-id
            (return-from handle-add-group-member (error-response "User ID is required")))
          (add-group-member id (if (stringp user-id) (parse-integer user-id) user-id))
          (json-response `(:message "Member added")))
        (error-response "Invalid group ID"))))

(defun handle-remove-group-member (env)
  "DELETE /api/groups/:id/members/:user_id"
  (let* ((path (getf env :path-info))
         (group-id (extract-id-from-path path "^/api/groups/(\\d+)/members/\\d+$"))
         (user-id-str (ppcre:register-groups-bind (uid)
                           ("^/api/groups/\\d+/members/(\\d+)$" path)
                         uid)))
    (if (and group-id user-id-str)
        (progn
          (remove-group-member group-id (parse-integer user-id-str))
          (json-response `(:message "Member removed")))
        (error-response "Invalid group or user ID"))))

;;; Ticket observer handlers

(defun handle-list-ticket-observers (env)
  "GET /api/tickets/:id/observers"
  (let ((ticket-id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)/observers$")))
    (if ticket-id
        (let ((observers (list-ticket-observers ticket-id)))
          (json-response `(:observers ,observers)))
        (error-response "Invalid ticket ID"))))

(defun handle-add-ticket-observer (env)
  "POST /api/tickets/:id/observers"
  (let ((ticket-id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)/observers$")))
    (if ticket-id
        (bind ((body (parse-json-body env))
               (observer-type (json-assoc :observer_type body))
               (observer-id (json-assoc :observer_id body)))
          (unless observer-type
            (return-from handle-add-ticket-observer (error-response "Observer type is required")))
          (unless observer-id
            (return-from handle-add-ticket-observer (error-response "Observer ID is required")))
          (add-ticket-observer ticket-id observer-type
                              (if (stringp observer-id) (parse-integer observer-id) observer-id))
          (let ((ticket (and ticket-id (get-ticket-by-id ticket-id))))
            (when ticket
              (ensure-board-member (getf ticket :board-id)
                                   observer-type
                                   (if (stringp observer-id)
                                       (parse-integer observer-id)
                                       observer-id))))
          (json-response `(:message "Observer added")))
        (error-response "Invalid ticket ID"))))

(defun handle-remove-ticket-observer (env)
  "DELETE /api/tickets/:id/observers/:type/:observer_id"
  (let* ((path (getf env :path-info))
         (ticket-id (extract-id-from-path path "^/api/tickets/(\\d+)/observers/.+$"))
         (parts (ppcre:register-groups-bind (tid observer-type observer-id)
                     ("^/api/tickets/(\\d+)/observers/(user|group)/(\\d+)$" path)
                   (list (when tid (parse-integer tid))
                         observer-type
                         (when observer-id (parse-integer observer-id))))))
    (if (and ticket-id (first parts) (second parts) (third parts))
        (progn
          (remove-ticket-observer ticket-id (second parts) (third parts))
          (json-response `(:message "Observer removed")))
        (error-response "Invalid ticket ID, observer type, or observer ID"))))

;;; Board handlers

(defun board-visibility-response (env)
  "Return 403 response if the user may not view the board."
  (let* ((user-id (get-user-id-from-env env))
         (board-id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)")))
    (when board-id
      (let* ((visible (list-visible-boards user-id))
             (found (find board-id visible :key (lambda (b) (getf b :id)))))
        (unless (or found (manager-p user-id))
          (error-response "Board not found or not accessible" 403))))))

(defun board-manage-error (board-id user-id)
  "Return 403 response unless the user may manage the board."
  (unless (can-manage-board board-id user-id)
    (error-response "You don't have permission to modify this board" 403)))

(defun handle-list-boards (env)
  "GET /api/boards"
  (let ((user-id (get-user-id-from-env env)))
    (json-response `(:boards ,(list-visible-boards user-id)))))

(defun handle-create-board (env)
  "POST /api/boards"
  (bind ((body (parse-json-body env))
         (name (json-assoc :name body))
         (type (json-assoc :type body))
         (user-id (get-user-id-from-env env)))
    (unless name
      (return-from handle-create-board (error-response "Name is required")))
    (let ((type (or type "personal")))
      (when (and (equal type "common") (not (manager-p user-id)))
        (return-from handle-create-board
          (error-response "Only admins and group managers can create common boards" 403)))
      (let ((board-id (create-board name type user-id)))
        ;; Shared boards: share with selected groups and users.
        (when (equal type "common")
          (iter (for group-id in (json-id-list (json-assoc :group_ids body)))
            (ensure-board-member board-id "group" group-id))
          (iter (for member-id in (json-id-list (json-assoc :user_ids body)))
            (ensure-board-member board-id "user" member-id)))
        (json-response `(:id ,board-id) 201)))))

(defun handle-get-board (env)
  "GET /api/boards/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)$")))
    (if id
        (let ((board (get-board-by-id id)))
          (if board
              (progn
                (let ((forbidden (board-visibility-response env)))
                  (when forbidden (return-from handle-get-board forbidden)))
                (json-response (list :id (getf board :id)
                                     :name (getf board :name)
                                     :type (getf board :type)
                                     :is_default (getf board :is-default)
                                     :owner_id (getf board :owner-id)
                                     :statuses (list-board-statuses id)
                                     :transitions (list-board-transitions id))))
              (error-response "Board not found" 404)))
        (error-response "Invalid board ID"))))

(defun handle-update-board (env)
  "PUT /api/boards/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)$")))
    (if id
        (let ((user-id (get-user-id-from-env env)))
          (let ((forbidden (board-manage-error id user-id)))
            (when forbidden (return-from handle-update-board forbidden)))
          (bind ((body (parse-json-body env))
                 (name (json-assoc :name body)))
            (json-response (update-board id :name name))))
        (error-response "Invalid board ID"))))

(defun handle-delete-board (env)
  "DELETE /api/boards/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)$")))
    (if id
        (let ((user-id (get-user-id-from-env env)))
          (let ((forbidden (board-manage-error id user-id)))
            (when forbidden (return-from handle-delete-board forbidden)))
          (delete-board id)
          (json-response `(:message "Board deleted")))
        (error-response "Invalid board ID"))))

(defun handle-list-board-members (env)
  "GET /api/boards/:id/members"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)/members$")))
    (if id
        (progn
          (let ((forbidden (board-visibility-response env)))
            (when forbidden (return-from handle-list-board-members forbidden)))
          (json-response `(:members ,(list-board-members id))))
        (error-response "Invalid board ID"))))

(defun handle-add-board-member (env)
  "POST /api/boards/:id/members"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)/members$")))
    (if id
        (let ((user-id (get-user-id-from-env env)))
          (let ((forbidden (board-manage-error id user-id)))
            (when forbidden (return-from handle-add-board-member forbidden)))
          (bind ((body (parse-json-body env))
                 (member-type (json-assoc :member_type body))
                 (member-id (json-assoc :member_id body)))
            (unless (and member-type member-id)
              (return-from handle-add-board-member
                (error-response "member_type and member_id are required")))
            (ensure-board-member id
                                 member-type
                                 (if (stringp member-id) (parse-integer member-id) member-id))
            (json-response `(:message "Member added"))))
        (error-response "Invalid board ID"))))

(defun handle-remove-board-member (env)
  "DELETE /api/boards/:id/members/:type/:member_id"
  (let* ((path (getf env :path-info))
         (board-id (extract-id-from-path path "^/api/boards/(\\d+)/members/.+$"))
         (parts (ppcre:register-groups-bind (bid member-type member-id)
                     ("^/api/boards/(\\d+)/members/(user|group)/(\\d+)$" path)
                   (list (when bid (parse-integer bid)) member-type
                         (when member-id (parse-integer member-id))))))
    (if (and board-id (second parts) (third parts))
        (let ((user-id (get-user-id-from-env env)))
          (let ((forbidden (board-manage-error (first parts) user-id)))
            (when forbidden (return-from handle-remove-board-member forbidden)))
          (remove-board-member (first parts) (second parts) (third parts))
          (json-response `(:message "Member removed")))
        (error-response "Invalid board, member type, or member ID"))))

(defun handle-list-board-statuses (env)
  "GET /api/boards/:id/statuses"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)/statuses$")))
    (if id
        (progn
          (let ((forbidden (board-visibility-response env)))
            (when forbidden (return-from handle-list-board-statuses forbidden)))
          (json-response `(:statuses ,(list-board-statuses id))))
        (error-response "Invalid board ID"))))

(defun handle-create-board-status (env)
  "POST /api/boards/:id/statuses"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)/statuses$")))
    (if id
        (let ((user-id (get-user-id-from-env env)))
          (let ((forbidden (board-manage-error id user-id)))
            (when forbidden (return-from handle-create-board-status forbidden)))
          (bind ((body (parse-json-body env))
                 (code (json-assoc :code body))
                 (name (json-assoc :name body))
                 (color (json-assoc :color body))
                 (position (json-assoc :position body)))
            (unless (and code name)
              (return-from handle-create-board-status
                (error-response "code and name are required")))
            (json-response `(:id ,(create-board-status id code name
                                                       :color color
                                                       :position (as-int position)))
                           201)))
        (error-response "Invalid board ID"))))

(defun handle-update-board-status (env)
  "PUT /api/boards/:id/statuses/:status_id"
  (let* ((path (getf env :path-info))
         (board-id (extract-id-from-path path "^/api/boards/(\\d+)/statuses/\\d+$"))
         (status-id (extract-id-from-path path "^/api/boards/\\d+/statuses/(\\d+)$")))
    (if (and board-id status-id)
        (let ((user-id (get-user-id-from-env env)))
          (let ((forbidden (board-manage-error board-id user-id)))
            (when forbidden (return-from handle-update-board-status forbidden)))
          (bind ((body (parse-json-body env))
                 (name (json-assoc :name body))
                 (color (json-assoc :color body))
                 (position (json-assoc :position body)))
            (update-board-status board-id status-id
                                 :name name
                                 :color color
                                 :position (as-int position))
            (json-response `(:message "Status updated"))))
        (error-response "Invalid board or status ID"))))

(defun handle-delete-board-status (env)
  "DELETE /api/boards/:id/statuses/:status_id"
  (let* ((path (getf env :path-info))
         (board-id (extract-id-from-path path "^/api/boards/(\\d+)/statuses/\\d+$"))
         (status-id (extract-id-from-path path "^/api/boards/\\d+/statuses/(\\d+)$")))
    (if (and board-id status-id)
        (let ((user-id (get-user-id-from-env env)))
          (let ((forbidden (board-manage-error board-id user-id)))
            (when forbidden (return-from handle-delete-board-status forbidden)))
          (delete-board-status board-id status-id)
          (json-response `(:message "Status deleted")))
        (error-response "Invalid board or status ID"))))

(defun handle-list-board-transitions (env)
  "GET /api/boards/:id/transitions"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)/transitions$")))
    (if id
        (progn
          (let ((forbidden (board-visibility-response env)))
            (when forbidden (return-from handle-list-board-transitions forbidden)))
          (json-response `(:transitions ,(list-board-transitions id))))
        (error-response "Invalid board ID"))))

(defun handle-add-board-transition (env)
  "POST /api/boards/:id/transitions"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)/transitions$")))
    (if id
        (let ((user-id (get-user-id-from-env env)))
          (let ((forbidden (board-manage-error id user-id)))
            (when forbidden (return-from handle-add-board-transition forbidden)))
          (bind ((body (parse-json-body env))
                 (from-code (json-assoc :from_code body))
                 (to-code (json-assoc :to_code body)))
            (unless (and from-code to-code)
              (return-from handle-add-board-transition
                (error-response "from_code and to_code are required")))
            (add-board-transition id from-code to-code)
            (json-response `(:message "Transition added"))))
        (error-response "Invalid board ID"))))

(defun handle-remove-board-transition (env)
  "DELETE /api/boards/:id/transitions/:from/:to"
  (let* ((path (getf env :path-info))
         (board-id (extract-id-from-path path "^/api/boards/(\\d+)/transitions/.+$"))
         (parts (ppcre:register-groups-bind (bid from-code to-code)
                     ("^/api/boards/(\\d+)/transitions/([^/]+)/([^/]+)$" path)
                   (list (when bid (parse-integer bid)) from-code to-code))))
    (if (and board-id (second parts) (third parts))
        (let ((user-id (get-user-id-from-env env)))
          (let ((forbidden (board-manage-error (first parts) user-id)))
            (when forbidden (return-from handle-remove-board-transition forbidden)))
          (remove-board-transition (first parts) (second parts) (third parts))
          (json-response `(:message "Transition removed")))
        (error-response "Invalid board, from_code, or to_code"))))
