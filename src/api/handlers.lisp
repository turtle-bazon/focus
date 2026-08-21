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

;;; API Routes

(defun plist-to-json (plist)
  "Convert a plist to a hash-table for JSON encoding. NIL values become the
   null sentinel so jzon emits null rather than false."
  (cond
    ((null plist) 'null)
    ((typep plist 'local-time:timestamp)
     (princ-to-string plist))
    ((and (listp plist) (keywordp (car plist)))
     (let ((ht (hash/empty #'equal)))
       (iter (for (key val) on plist by #'cddr)
         (hash/put ht
                   (if (keywordp key)
                       (substitute #\_ #\- (string-downcase (symbol-name key)))
                       (format nil "~a" key))
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
        (list (jzon:stringify (plist-to-json data)))))

(defun error-response (message &optional (status 400))
  "Create an error response."
  (json-response `(:error ,message) status))

(defun json-normalize (value)
  "Map the JSON null sentinel to NIL so null behaves like a missing value."
  (if (eq value 'null) nil value))

(defun json-assoc (key obj)
  "Look up KEY (a keyword) in a parsed JSON object OBJ (hash-table with
   string keys). Tries the literal downcased name, then the underscore/
   hyphen-swapped variant. JSON null and false both read as NIL."
  (when (hash-table-p obj)
    (let ((name (string-downcase (symbol-name key))))
      (multiple-value-bind (value present-p) (gethash name obj)
        (if present-p
            (json-normalize value)
            (json-normalize
             (gethash (substitute #\- #\_ name) obj)))))))

(defun as-int (value)
  "Coerce a JSON value to an integer. jzon decodes numbers as integers,
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

(defun read-stream-bytes (stream)
  "Read STREAM to EOF, returning all bytes as a single octet vector."
  (iter (for chunk = (make-array 8192 :element-type '(unsigned-byte 8)))
        (for n = (read-sequence chunk stream))
        (when (plusp n)
          (collect (subseq chunk 0 n) into parts)
          (sum n into total))
        (until (< n (length chunk)))
        (finally (return
                   (let ((out (make-array total :element-type '(unsigned-byte 8))))
                     (iter (for part in parts)
                           (for pos initially 0 then (+ pos (length part)))
                           (replace out part :start1 pos))
                     out)))))

(defun raw-body-string (env)
  "Read the raw request body from ENV as a UTF-8 string."
  (let ((body (getf env :raw-body)))
    (when body
      (flexi-streams:octets-to-string
       (if (typep body 'stream)
           (read-stream-bytes body)
           body)
       :external-format :utf-8))))

(defun parse-json-body (env)
  "Parse the JSON request body from Clack env into jzon structures
   (hash-tables, vectors, atoms), or NIL when absent or malformed."
  (let ((content (raw-body-string env)))
    (when (and content (> (length content) 0))
      (ignore-errors (jzon:parse content)))))

(defun percent-decode (str)
  "Decode percent-encoded octets in STR (e.g. '%20' -> space)."
  (when str
    (let ((out (make-array (length str) :element-type 'character :fill-pointer 0)))
      (iter (for i from 0 below (length str))
        (let ((ch (char str i)))
          (if (and (char= ch #\%)
                   (< (+ i 2) (length str)))
              (if-let (hex (parse-integer (subseq str (1+ i) (+ i 3))
                                          :radix 16 :junk-allowed t))
                  (progn
                    (vector-push-extend (code-char hex) out)
                    (incf i 2))
                  (vector-push-extend ch out))
              (vector-push-extend ch out))))
      (coerce out 'string))))

(defun parse-query-string (query-string)
  "Parse a URL query string into an alist of percent-decoded pairs."
  (when (and query-string (plusp (length query-string)))
    (iter (for pair in (string/split query-string #\&))
      (collecting (let ((kv (string/split pair #\=)))
                    (let ((key (percent-decode (car kv)))
                          (value (percent-decode (cadr kv))))
                      (cons key value)))))))

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
  (when-let (session-id (cl-oauth2:get-session-id-from-request env))
    (when-let (db-session (get-db-session session-id))
      (getf db-session :user-id))))

(defun get-actor (env)
  "Return the acting identity as a plist, or nil. For a session cookie user:
   (:user-id N). For an agent envelope request: (:agent-id N :user-id <owner>
   :agent <plist>) from the :focus-agent injected by handle-agent-envelope."
  (or (when-let (uid (get-user-id-from-env env))
        (list :user-id uid))
      (when-let (agent (getf env :focus-agent))
        (list :agent-id (getf agent :id)
              :user-id (getf agent :owner-id)
              :agent agent))))

(defun log-activity (ticket-id actor-id action &key agent-id details)
  "Log an activity entry and broadcast it live. Silently ignores errors.
   Returns the activity ID or NIL. ACTOR-ID is the user id (for agents: the
   owner); AGENT-ID tags the activity as performed by an agent."
  (when actor-id
    (handler-case
        (let ((id (create-activity ticket-id actor-id action
                                   :agent-id agent-id :details details)))
          (ws-broadcast-activity-created (get-activity-with-context id))
          id)
      (error (e)
        (bl:warn "Failed to log activity: ~a" e)))))

(defun actor-board-access-error (env board-id)
  "Return 403 response unless the actor may act on BOARD-ID. Agents are capped
   by membership ∩ owner-access; users by their visibility."
  (when board-id
    (let* ((actor (get-actor env))
           (agent (when (and actor (getf actor :agent)) (getf actor :agent))))
      (cond
        (actor
         (let ((visible (if agent
                            (agent-visible-boards agent)
                            (list-visible-boards (getf actor :user-id)))))
           (unless (find board-id visible :key (lambda (b) (getf b :id)))
             (error-response "Board not found or not accessible" 403))))
        (t (error-response "Not authenticated" 401))))))

(defun actor-agent-id (env)
  "Return the acting agent's ID, or nil for session users."
  (let ((actor (get-actor env)))
    (when (and actor (getf actor :agent-id))
      (getf actor :agent-id))))

(defun actor-user-id (env)
  "Return the acting user id (for agents, their owner)."
  (let ((actor (get-actor env)))
    (getf actor :user-id)))

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
                                :limit limit))
         (total (count-tickets :status status
                               :priority priority
                               :assignee-id assignee-id
                               :board-id board-id)))
    (json-response `(:tickets ,(or tickets (make-array 0)) :total ,total))))

(defun handle-get-ticket (env)
  "GET /api/tickets/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)$")))
    (if id
        (let ((ticket (get-ticket-by-id id)))
          (if ticket
              (let ((actor (get-actor env)))
                (when (and actor (getf actor :agent))
                  (unless (agent-can-view-board (getf ticket :board-id)
                                                (getf actor :agent))
                    (return-from handle-get-ticket
                      (error-response "Ticket not found" 404))))
                (json-response ticket))
              (error-response "Ticket not found" 404)))
        (error-response "Invalid ticket ID"))))

(defun ticket-body-fields (body)
  "Parse the common ticket fields from a JSON BODY alist into a plist,
   coercing numeric IDs given as strings."
  (list :title (json-assoc :title body)
        :description (json-assoc :description body)
        :status (json-assoc :status body)
        :priority (json-assoc :priority body)
        :assignee-id (as-int (json-assoc :assignee_id body))
        :assignee-type (json-assoc :assignee_type body)
        :color (json-assoc :color body)
        :position (json-assoc :position body)
        :board-id (as-int (json-assoc :board_id body))))

(defun ensure-assignee-board-member (board-id assignee-type assignee-id)
  "Make the ASSIGNEE a member of BOARD-ID (member type defaults to user)."
  (when (and board-id assignee-id)
    (ensure-board-member board-id (or assignee-type "user") assignee-id)))

(defun actor-ids (env)
  "Return (values user-id agent-id) for the acting identity."
  (let ((actor (get-actor env)))
    (values (or (getf actor :user-id) (get-user-id-from-env env))
            (getf actor :agent-id))))

(defun handle-create-ticket (env)
  "POST /api/tickets"
  (bind ((fields (ticket-body-fields (parse-json-body env)))
         (title (getf fields :title))
         (board-id (getf fields :board-id)))
    (unless title
      (return-from handle-create-ticket (error-response "Title is required")))
    (when board-id
      (let ((forbidden (actor-board-access-error env board-id)))
        (when forbidden (return-from handle-create-ticket forbidden))))
    (bind ((id (create-ticket title
                              :description (getf fields :description)
                              :status (getf fields :status)
                              :priority (getf fields :priority)
                              :assignee-id (getf fields :assignee-id)
                              :assignee-type (getf fields :assignee-type)
                              :color (getf fields :color)
                              :board-id board-id))
           (ticket (get-ticket-by-id id)))
      (multiple-value-bind (user-id agent-id) (actor-ids env)
        (ensure-assignee-board-member (getf ticket :board-id)
                                      (getf fields :assignee-type)
                                      (getf fields :assignee-id))
        (log-activity id user-id "created"
                      :agent-id agent-id
                      :details `((:title . ,title)))
        (ws-broadcast-ticket-created ticket)
        (json-response `(:id ,id) 201)))))

(defun validate-status-transition (old-ticket new-board status)
  "Enforce lifecycle transitions when STATUS changes. Returns
   (values error-response-or-nil coerced-status). On an unchanged board every
   move must be allowed by the workflow; on a board change an unknown status
   falls back to the destination board's first status."
  (if (and status (not (equal status (getf old-ticket :status))))
      (if (equal new-board (getf old-ticket :board-id))
          (if (transition-allowed-p new-board (getf old-ticket :status) status)
              (values nil status)
              (values (error-response
                       "Status transition is not allowed by this board's workflow")
                      status))
          (let ((codes (iter (for s in (list-board-statuses new-board))
                         (collecting (getf s :code)))))
            (values nil
                    (if (member status codes :test #'string=)
                        status
                        (car codes)))))
      (values nil status)))

(defun ensure-moved-ticket-members (new-board ticket id)
  "After moving TICKET to NEW-BOARD, re-ensure its assignee and observers
   belong to the destination."
  (when (getf ticket :assignee-id)
    (ensure-board-member new-board
                         (or (getf ticket :assignee-type) "user")
                         (getf ticket :assignee-id)))
  (iter (for obs in (list-ticket-observers id))
    (ensure-board-member new-board
                         (getf obs :observer_type)
                         (getf obs :observer_id))))

(defun log-ticket-update-activity (id user-id agent-id old-ticket title status priority)
  "Log status/priority/title change activity for an updated ticket. A change
   is only recorded for fields the request actually supplied."
  (let ((status-changed (and status (not (equal (getf old-ticket :status) status))))
        (priority-changed (and priority (not (equal (getf old-ticket :priority) priority))))
        (title-changed (and title (not (equal (getf old-ticket :title) title)))))
    (when (and status-changed priority-changed)
      (log-activity id user-id "status_priority_changed"
                    :agent-id agent-id
                    :details `(("old-status" . ,(getf old-ticket :status))
                               ("new-status" . ,status)
                               ("old-priority" . ,(getf old-ticket :priority))
                               ("new-priority" . ,priority))))
    (when (and status-changed (not priority-changed))
      (log-activity id user-id "status_changed"
                    :agent-id agent-id
                    :details `((:from . ,(getf old-ticket :status)) (:to . ,status))))
    (when (and priority-changed (not status-changed))
      (log-activity id user-id "priority_changed"
                    :agent-id agent-id
                    :details `((:from . ,(getf old-ticket :priority)) (:to . ,priority))))
    (when title-changed
      (log-activity id user-id "title_changed"
                    :agent-id agent-id
                    :details `((:from . ,(getf old-ticket :title)) (:to . ,title))))))

(defun apply-ticket-update (id fields old-ticket new-board env)
  "Persist the update (or reposition), run post-update side effects, and
   return the final Clack response."
  (multiple-value-bind (transition-error status)
      (validate-status-transition old-ticket new-board (getf fields :status))
    (when transition-error
      (return-from apply-ticket-update transition-error))
    (bind ((ticket (if (getf fields :position)
                       (reposition-ticket id
                                          (or status (getf old-ticket :status))
                                          (or (getf fields :priority) "medium")
                                          (getf fields :position))
                       (update-ticket id
                                      :title (getf fields :title)
                                      :description (getf fields :description)
                                      :status status
                                      :priority (getf fields :priority)
                                      :assignee-id (getf fields :assignee-id)
                                      :assignee-type (getf fields :assignee-type)
                                      :color (getf fields :color)
                                      :board-id (when (getf fields :board-id) new-board)))))
      (if ticket
          (progn
            (unless (equal new-board (getf old-ticket :board-id))
              ;; Moving to another board: re-ensure assignee and observers.
              (ensure-moved-ticket-members new-board ticket id))
            (ensure-assignee-board-member (getf ticket :board-id)
                                          (getf fields :assignee-type)
                                          (getf fields :assignee-id))
            (multiple-value-bind (user-id agent-id) (actor-ids env)
              (log-ticket-update-activity id user-id agent-id old-ticket
                                          (getf fields :title) status
                                          (getf fields :priority))
              ;; Any edit makes the editor an observer of the ticket.
              (when (and user-id (get-user-by-id user-id))
                (add-ticket-observer id "user" user-id)))
            (ws-broadcast-ticket-update ticket)
            (json-response ticket))
          (error-response "Ticket not found" 404)))))

(defun handle-update-ticket (env)
  "PUT /api/tickets/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)$")))
    (unless id
      (return-from handle-update-ticket (error-response "Invalid ticket ID")))
    (bind ((fields (ticket-body-fields (parse-json-body env)))
           (old-ticket (get-ticket-by-id id))
           (new-board (or (getf fields :board-id) (getf old-ticket :board-id))))
      (unless old-ticket
        (return-from handle-update-ticket (error-response "Ticket not found" 404)))
      (let ((forbidden (actor-board-access-error env (getf old-ticket :board-id))))
        (when forbidden (return-from handle-update-ticket forbidden)))
      (apply-ticket-update id fields old-ticket new-board env))))

(defun handle-delete-ticket (env)
  "DELETE /api/tickets/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)$")))
    (if id
        (let ((ticket (get-ticket-by-id id)))
          (if ticket
              (progn
                (delete-ticket id)
                (ws-broadcast-ticket-deleted ticket)
                (json-response `(:message "Ticket deleted")))
              (error-response "Ticket not found" 404)))
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
               (agent-id (actor-agent-id env))
               (user-id (or (actor-user-id env)
                            (when (null agent-id)
                              (json-assoc :user_id body))))
               (comment-body (json-assoc :body body)))
          (unless (or user-id agent-id)
            (return-from handle-create-comment (error-response "User ID is required")))
          (unless comment-body
            (return-from handle-create-comment (error-response "Body is required")))
          (let ((ticket (get-ticket-by-id ticket-id)))
            (when ticket
              (let ((forbidden (actor-board-access-error env (getf ticket :board-id))))
                (when forbidden (return-from handle-create-comment forbidden)))))
          (bind ((id (create-comment ticket-id
                                     user-id
                                     comment-body
                                     :agent-id agent-id))
                 (comment (get-comment-by-id id)))
            (log-activity ticket-id
                          user-id
                          "comment_added"
                          :agent-id agent-id
                          :details `((:user_id . ,user-id) (:body . ,comment-body)))
            ;; Commenting makes the commenter an observer of the ticket.
            (when user-id
              (add-ticket-observer ticket-id "user" user-id))
            (ws-broadcast-comment-created comment ticket-id
                                          (getf (get-ticket-by-id ticket-id) :board-id))
            (log-activity ticket-id
                          user-id
                          "comment_added"
                          :agent-id agent-id
                          :details `((:user_id . ,user-id) (:body . ,comment-body)))
            (json-response `(:id ,id) 201)))
        (error-response "Invalid ticket ID"))))

(defun handle-delete-comment (env)
  "DELETE /api/tickets/:ticket-id/comments/:comment-id"
  (let ((ticket-id nil) (comment-id nil))
    (ppcre:register-groups-bind (tid cid)
        ("^/api/tickets/(\\d+)/comments/(\\d+)$" (getf env :path-info))
      (setf ticket-id (parse-integer tid) comment-id (parse-integer cid)))
    (if (and ticket-id comment-id)
        (let ((comment (get-comment-by-id comment-id)))
          (cond ((null comment)
                 (error-response "Comment not found" 404))
                ((not (eql (getf comment :ticket-id) ticket-id))
                 (error-response "Comment not found" 404))
                (t
                 (let ((ticket (get-ticket-by-id ticket-id)))
                   (if ticket
                       (let ((forbidden (actor-board-access-error env (getf ticket :board-id))))
                         (if forbidden
                             forbidden
                             (progn
                               (delete-comment comment-id)
                               (json-response `(:message "Comment deleted")))))
                       (error-response "Ticket not found" 404))))))
        (error-response "Invalid comment ID"))))

(defun handle-modify-ticket-label (env add?)
  "Shared impl for adding/removing a label (by ID) on a ticket."
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)/labels/\\w+$")))
    (if id
        (let ((label (extract-id-from-path (getf env :path-info)
                                           "^/api/tickets/\\d+/labels/(\\d+)$")))
          (if label
              (let ((ticket (get-ticket-by-id id)))
                (if ticket
                    (let ((forbidden (actor-board-access-error env (getf ticket :board-id))))
                      (if forbidden
                          forbidden
                          (progn
                            (if add?
                                (add-label-to-ticket id label)
                                (remove-label-from-ticket id label))
                            (json-response `(:labels ,(get-ticket-labels id))))))
                    (error-response "Ticket not found" 404)))
              (error-response "Invalid label ID")))
        (error-response "Invalid ticket ID"))))

(defun handle-add-ticket-label (env)
  "POST /api/tickets/:id/labels/:ref — add a label (by ID) to a ticket."
  (handle-modify-ticket-label env t))

(defun handle-remove-ticket-label (env)
  "DELETE /api/tickets/:id/labels/:ref — remove a label (by ID) from a ticket."
  (handle-modify-ticket-label env nil))

(defun handle-list-ticket-labels (env)
  "GET /api/tickets/:id/labels — list labels on a ticket."
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/tickets/(\\d+)/labels$")))
    (if id
        (let ((ticket (get-ticket-by-id id)))
          (if ticket
              (let ((forbidden (actor-board-access-error env (getf ticket :board-id))))
                (if forbidden
                    forbidden
                    (json-response `(:labels ,(get-ticket-labels id)))))
              (error-response "Ticket not found" 404)))
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
         (actor (get-actor env))
         (user-id (if (and actor (getf actor :user-id))
                      (getf actor :user-id)
                      (get-user-id-from-env env)))
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
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (declare (ignore user-id))
    (if forbidden
        forbidden
        (json-response `(:users ,(list-users))))))

(defun handle-create-user (env)
  "POST /api/users"
  (multiple-value-bind (user-id forbidden) (require-role-user env '("admin"))
    (declare (ignore user-id))
    (when forbidden
      (return-from handle-create-user forbidden))
    (bind ((body (parse-json-body env))
           (username (json-assoc :username body))
           (email (json-assoc :email body)))
      (unless username
        (return-from handle-create-user (error-response "Username is required")))
      (unless email
        (return-from handle-create-user (error-response "Email is required")))
      (bind ((id (create-user username email)))
        (json-response `(:id ,id) 201)))))

(defun handle-update-user (env)
  "PUT /api/users/:id"
  (multiple-value-bind (user-id forbidden) (require-role-user env '("admin"))
    (declare (ignore user-id))
    (when forbidden
      (return-from handle-update-user forbidden))
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
          (error-response "Invalid user ID")))))

(defun handle-delete-user (env)
  "DELETE /api/users/:id"
  (multiple-value-bind (user-id forbidden) (require-role-user env '("admin"))
    (declare (ignore user-id))
    (when forbidden
      (return-from handle-delete-user forbidden))
    (let ((id (extract-id-from-path (getf env :path-info) "^/api/users/(\\d+)$")))
      (if id
          (progn (delete-user id)
                 (json-response `(:message "User deleted")))
          (error-response "Invalid user ID")))))

(defun handle-undelete-user (env)
  "POST /api/users/:id/undelete"
  (multiple-value-bind (user-id forbidden) (require-role-user env '("admin"))
    (declare (ignore user-id))
    (when forbidden
      (return-from handle-undelete-user forbidden))
    (let ((id (extract-id-from-path (getf env :path-info) "^/api/users/(\\d+)/undelete$")))
      (if id
          (progn (undelete-user id)
                 (json-response `(:message "User restored")))
          (error-response "Invalid user ID")))))

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
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (declare (ignore user-id))
    (if forbidden
        forbidden
        (json-response `(:groups ,(list-groups))))))

(defun handle-create-group (env)
  "POST /api/groups"
  (multiple-value-bind (user-id forbidden)
      (require-role-user env '("admin" "group_manager"))
    (declare (ignore user-id))
    (when forbidden
      (return-from handle-create-group forbidden))
    (bind ((body (parse-json-body env))
           (name (json-assoc :name body)))
      (unless name
        (return-from handle-create-group (error-response "Name is required")))
      (bind ((id (create-group name)))
        (json-response `(:id ,id) 201)))))

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
  (multiple-value-bind (user-id forbidden)
      (require-role-user env '("admin" "group_manager"))
    (declare (ignore user-id))
    (when forbidden
      (return-from handle-update-group forbidden))
    (let ((id (extract-id-from-path (getf env :path-info) "^/api/groups/(\\d+)$")))
      (if id
          (bind ((body (parse-json-body env))
                 (name (json-assoc :name body)))
            (update-group id :name name)
            (json-response (get-group-by-id id)))
          (error-response "Invalid group ID")))))

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
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (declare (ignore user-id))
    (when forbidden
      (return-from handle-list-group-members forbidden))
    (let ((id (extract-id-from-path (getf env :path-info) "^/api/groups/(\\d+)/members$")))
      (if id
          (json-response `(:members ,(list-group-members id)))
          (error-response "Invalid group ID")))))

(defun handle-add-group-member (env)
  "POST /api/groups/:id/members"
  (multiple-value-bind (user-id forbidden)
      (require-role-user env '("admin" "group_manager"))
    (declare (ignore user-id))
    (when forbidden
      (return-from handle-add-group-member forbidden))
    (let ((id (extract-id-from-path (getf env :path-info) "^/api/groups/(\\d+)/members$")))
      (if id
          (bind ((body (parse-json-body env))
                 (user-id (json-assoc :user_id body)))
            (unless user-id
              (return-from handle-add-group-member (error-response "User ID is required")))
            (add-group-member id (if (stringp user-id) (parse-integer user-id) user-id))
            (json-response `(:message "Member added")))
          (error-response "Invalid group ID")))))

(defun handle-remove-group-member (env)
  "DELETE /api/groups/:id/members/:user_id"
  (multiple-value-bind (user-id forbidden)
      (require-role-user env '("admin" "group_manager"))
    (declare (ignore user-id))
    (when forbidden
      (return-from handle-remove-group-member forbidden))
    (let* ((path (getf env :path-info))
           (group-id (extract-id-from-path path "^/api/groups/(\\d+)/members/\\d+$"))
           (user-id-str (ppcre:register-groups-bind (uid)
                             ("^/api/groups/\\d+/members/(\\d+)$" path)
                           uid)))
      (if (and group-id user-id-str)
          (progn
            (remove-group-member group-id (parse-integer user-id-str))
            (json-response `(:message "Member removed")))
          (error-response "Invalid group or user ID")))))

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
  (let* ((actor (get-actor env))
         (board-id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)")))
    (when board-id
      (let* ((agent (when (and actor (getf actor :agent))
                      (getf actor :agent)))
             (visible (cond
                        (agent (agent-visible-boards agent))
                        ((getf actor :user-id) (list-visible-boards (getf actor :user-id)))
                        (t (list-visible-boards nil))))
             (found (find board-id visible :key (lambda (b) (getf b :id)))))
        (unless (or found
                    (and (not agent)
                         (getf actor :user-id)
                         (manager-p (getf actor :user-id))))
          (if (null actor)
              (error-response "Not authenticated" 401)
              (error-response "Board not found or not accessible" 403)))))))

(defun board-manage-error (board-id user-id)
  "Return 403 response unless USER-ID may manage the board. Agent calls pass
   NIL here and are handled separately (agents never manage)."
  (unless (can-manage-board board-id user-id)
    (error-response "You don't have permission to modify this board" 403)))

(defun board-manager-check (board-id env)
  "Return a 403 response unless the session user of ENV may manage BOARD-ID."
  (board-manage-error board-id (get-user-id-from-env env)))

(defun board-member-change-permitted (env board-id member-type member-id user-id)
  "Return NIL if the actor may add/remove MEMBER-TYPE/MEMBER-ID on BOARD-ID,
   or a 403 response otherwise. Any user may manage their own agents on boards
   they can access; all other member types require board management rights."
  (if (and (string= member-type "agent") user-id)
      (or (board-visibility-response env)
          (let ((agent (get-agent-by-id member-id)))
            (unless (and agent (= (getf agent :owner-id) user-id))
              (error-response "You can only manage your own agents" 403))))
      (board-manage-error board-id user-id)))

(defun handle-list-boards (env)
  "GET /api/boards"
  (let* ((actor (get-actor env))
         (agent (when (and actor (getf actor :agent)) (getf actor :agent)))
         (boards (cond
                   (agent (agent-visible-boards agent))
                   (t (list-visible-boards (getf actor :user-id))))))
    (json-response `(:boards ,boards))))

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
            (ensure-board-member board-id "user" member-id))
          (iter (for agent-id in (json-id-list (json-assoc :agent_ids body)))
            ;; Only the owner's own agents can be shared.
            (when (= user-id (getf (get-agent-by-id agent-id) :owner-id))
              (ensure-board-member board-id "agent" agent-id))))
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
        (progn
          (let ((forbidden (board-manager-check id env)))
            (when forbidden (return-from handle-update-board forbidden)))
          (bind ((body (parse-json-body env))
                 (name (json-assoc :name body)))
            (json-response (update-board id :name name))))
        (error-response "Invalid board ID"))))

(defun handle-delete-board (env)
  "DELETE /api/boards/:id"
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)$")))
    (if id
        (progn
          (let ((forbidden (board-manager-check id env)))
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
  "POST /api/boards/:id/members — managers may add any member; any user may
   add their own agents to a board they can access."
  (let ((id (extract-id-from-path (getf env :path-info) "^/api/boards/(\\d+)/members$")))
    (if id
        (let ((user-id (get-user-id-from-env env)))
          (bind ((body (parse-json-body env))
                 (member-type (json-assoc :member_type body))
                 (member-id (json-assoc :member_id body)))
            (unless (and member-type member-id)
              (return-from handle-add-board-member
                (error-response "member_type and member_id are required")))
            (let ((member-id (if (stringp member-id) (parse-integer member-id) member-id)))
              (let ((forbidden (board-member-change-permitted env id member-type member-id user-id)))
                (when forbidden (return-from handle-add-board-member forbidden)))
              (ensure-board-member id member-type member-id)
              (json-response `(:message "Member added")))))
        (error-response "Invalid board ID"))))

(defun handle-remove-board-member (env)
  "DELETE /api/boards/:id/members/:type/:member_id"
  (let* ((path (getf env :path-info))
         (board-id (extract-id-from-path path "^/api/boards/(\\d+)/members/.+$"))
         (parts (ppcre:register-groups-bind (bid member-type member-id)
                     ("^/api/boards/(\\d+)/members/(user|group|agent)/(\\d+)$" path)
                   (list (when bid (parse-integer bid)) member-type
                         (when member-id (parse-integer member-id))))))
    (if (and board-id (second parts) (third parts))
        (let ((user-id (get-user-id-from-env env)))
          (let ((forbidden (board-member-change-permitted
                            env (first parts) (second parts) (third parts) user-id)))
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
        (progn
          (let ((forbidden (board-manager-check id env)))
            (when forbidden (return-from handle-create-board-status forbidden)))
          (bind ((body (parse-json-body env))
                 (code (json-assoc :code body))
                 (name (json-assoc :name body))
                 (color (json-assoc :color body))
                 (position (json-assoc :position body))
                 (load-count (json-assoc :load_count body)))
            (unless (and code name)
              (return-from handle-create-board-status
                (error-response "code and name are required")))
            (json-response `(:id ,(create-board-status id code name
                                                       :color color
                                                       :position (as-int position)
                                                       :load-count (as-int load-count)))
                           201)))
        (error-response "Invalid board ID"))))

(defun handle-update-board-status (env)
  "PUT /api/boards/:id/statuses/:status_id"
  (let* ((path (getf env :path-info))
         (board-id (extract-id-from-path path "^/api/boards/(\\d+)/statuses/\\d+$"))
         (status-id (extract-id-from-path path "^/api/boards/\\d+/statuses/(\\d+)$")))
    (if (and board-id status-id)
        (progn
          (let ((forbidden (board-manager-check board-id env)))
            (when forbidden (return-from handle-update-board-status forbidden)))
          (bind ((body (parse-json-body env))
                 (name (json-assoc :name body))
                 (color (json-assoc :color body))
                 (position (json-assoc :position body))
                 (load-count (json-assoc :load_count body)))
            (update-board-status board-id status-id
                                 :name name
                                 :color color
                                 :position (as-int position)
                                 :load-count (as-int load-count))
            (json-response `(:message "Status updated"))))
        (error-response "Invalid board or status ID"))))

(defun handle-delete-board-status (env)
  "DELETE /api/boards/:id/statuses/:status_id"
  (let* ((path (getf env :path-info))
         (board-id (extract-id-from-path path "^/api/boards/(\\d+)/statuses/\\d+$"))
         (status-id (extract-id-from-path path "^/api/boards/\\d+/statuses/(\\d+)$")))
    (if (and board-id status-id)
        (progn
          (let ((forbidden (board-manager-check board-id env)))
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
        (progn
          (let ((forbidden (board-manager-check id env)))
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
        (progn
          (let ((forbidden (board-manager-check (first parts) env)))
            (when forbidden (return-from handle-remove-board-transition forbidden)))
          (remove-board-transition (first parts) (second parts) (third parts))
          (json-response `(:message "Transition removed")))
        (error-response "Invalid board, from_code, or to_code"))))

;;; Agent envelope (POST /api/agent)

(defun agent-shape-master-key (shape)
  "Compute the envelope master key for SHAPE from the server's private half."
  (envelope-master-key
   (x25519-shared-secret
    (x25519-import-private (getf shape :server-private))
    (x25519-import-public (getf shape :agent-public)))))

(defun make-agent-env (method path query body-string agent)
  "Build a synthetic Clack env carrying AGENT's identity and the decrypted
   inner request, ready for the router."
  (list :request-method (when method (intern (string-upcase method) :keyword))
        :path-info path
        :query-string query
        :raw-body (when body-string
                    (flexi-streams:string-to-octets body-string
                                                    :external-format :utf-8))
        :focus-agent agent))

(defun valid-agent-request-p (method path)
  "Only plain API methods and paths other than /api/agent may be tunneled."
  (and method path
       (member (intern (string-upcase method) :keyword)
               '(:get :post :put :delete))
       (ppcre:scan "^/api/" path)
       (not (ppcre:scan "^/api/agent" path))))

(defun response-body-text (body)
  "Flatten a Clack response BODY into text for the agent envelope."
  (cond
    ((null body) "")
    ((stringp body) body)
    ((and (consp body) (stringp (first body))) (first body))
    (t "")))

(defun make-agent-envelope-response (master response)
  "Encrypt an inner HTTP RESPONSE (a Clack list) into the envelope returned
   by POST /api/agent. The outer status mirrors the inner one."
  (let* ((status (first response))
         (inner (jzon:stringify
                 (hash/make (list (list "status" status)
                                  (list "body" (response-body-text (third response))))
                            :test #'equal)))
         (ts (get-universal-time)))
    (multiple-value-bind (nonce ciphertext tag)
        (envelope-encrypt master +envelope-direction-response+ ts
                          (flexi-streams:string-to-octets inner
                                                          :external-format :utf-8))
      (list status
            '(:content-type "application/json")
            (list (envelope-encode-json ts nonce ciphertext tag))))))

(defun handle-agent-envelope (env)
  "POST /api/agent — decrypt an agent envelope, run the inner request through
   the router as the shape's agent, and return an encrypted envelope."
  (let* ((token (bearer-token-from-env env))
         (shape (when token (get-agent-shape-by-bearer token))))
    (unless (and token shape)
      (return-from handle-agent-envelope (error-response "Unauthorized" 401)))
    (multiple-value-bind (ts nonce ciphertext tag)
        (ignore-errors (envelope-parse-json (raw-body-string env)))
      (unless ts
        (return-from handle-agent-envelope (error-response "Invalid envelope" 400)))
      (unless (envelope-time-fresh-p ts (config->envelope-window-seconds *config*))
        (return-from handle-agent-envelope
          (error-response "Envelope timestamp outside the freshness window" 400)))
      (handler-case
          (let* ((master (agent-shape-master-key shape))
                 (plaintext (envelope-decrypt master +envelope-direction-request+
                                              ts nonce ciphertext tag))
                 (request (jzon:parse
                           (flexi-streams:octets-to-string plaintext
                                                           :external-format :utf-8)))
                 (method (json-assoc :method request))
                 (path (json-assoc :path request)))
            (unless (valid-agent-request-p method path)
              (return-from handle-agent-envelope
                (error-response "Invalid inner request" 400)))
            (make-agent-envelope-response
             master
             (funcall *router*
                      (make-agent-env method path
                                      (or (json-assoc :query request) "")
                                      (json-assoc :body request)
                                      (get-agent-by-id (getf shape :agent-id))))))
        (ironclad:bad-authentication-tag ()
          (error-response "Envelope authentication failed" 401))))))

;;; Agent handlers

(defun require-session-user (env)
  "Return the session user ID or short-circuit with a 401 response.
   Agents may never manage agents or boards, so these endpoints are
   session-cookie authenticated only. Returns (values id response-or-nil)."
  (let ((user-id (get-user-id-from-env env)))
    (cond
      (user-id (values user-id nil))
      ((get-actor env) (values nil (error-response "Agents cannot manage agents or boards" 403)))
      (t (values nil (error-response "Not authenticated" 401))))))

(defun user-role (user-id)
  "Return the role of USER-ID (or nil if unknown)."
  (getf (get-user-by-id user-id) :role))

(defun require-role-user (env roles)
  "Return the session user ID if its role is in ROLES, or short-circuit
   with a 401/403 response. Returns (values id response-or-nil)."
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (if forbidden
        (values nil forbidden)
        (if (member (user-role user-id) roles :test #'string=)
            (values user-id nil)
            (values nil (error-response "Insufficient permissions" 403))))))

(defun handle-list-agents (env)
  "GET /api/agents — list the acting user's agents."
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (if forbidden
        forbidden
        (json-response `(:agents ,(list-agents :owner-id user-id))))))

(defun handle-create-agent (env)
  "POST /api/agents — create an agent owned by the acting user."
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (if forbidden
        forbidden
        (bind ((body (parse-json-body env))
               (name (json-assoc :name body))
               (description (json-assoc :description body)))
          (unless name
            (return-from handle-create-agent (error-response "Name is required")))
          (let ((id (create-agent user-id name :description description)))
            (json-response `(:id ,id) 201))))))

(defun owned-agent-error (id user-id)
  "Return a 404 response unless the agent ID exists and belongs to USER-ID."
  (let ((agent (get-agent-by-id id)))
    (unless (and agent (= (getf agent :owner-id) user-id))
      (error-response "Agent not found" 404))))

(defun handle-get-agent (env)
  "GET /api/agents/:id"
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (if forbidden
        forbidden
        (let ((id (extract-id-from-path (getf env :path-info) "^/api/agents/(\\d+)$")))
          (let ((denied (owned-agent-error id user-id)))
            (if denied
                denied
                (json-response `(:agent ,(get-agent-by-id id)))))))))

(defun handle-update-agent (env)
  "PUT /api/agents/:id"
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (if forbidden
        forbidden
        (let ((id (extract-id-from-path (getf env :path-info) "^/api/agents/(\\d+)$")))
          (let ((denied (owned-agent-error id user-id)))
            (when denied (return-from handle-update-agent denied)))
          (bind ((body (parse-json-body env))
                 (name (json-assoc :name body))
                 (description (json-assoc :description body)))
            (json-response `(:agent ,(update-agent id :name name :description description))))))))

(defun handle-delete-agent (env)
  "DELETE /api/agents/:id"
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (if forbidden
        forbidden
        (let ((id (extract-id-from-path (getf env :path-info) "^/api/agents/(\\d+)$")))
          (let ((denied (owned-agent-error id user-id)))
            (when denied (return-from handle-delete-agent denied)))
          (delete-agent id)
          (json-response `(:message "Agent deleted"))))))

(defun handle-list-agent-shapes (env)
  "GET /api/agents/:id/shapes"
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (if forbidden
        forbidden
        (let ((id (extract-id-from-path (getf env :path-info) "^/api/agents/(\\d+)/shapes$")))
          (let ((denied (owned-agent-error id user-id)))
            (if denied
                denied
                (json-response `(:shapes ,(list-agent-shapes id)))))))))

(defun handle-create-agent-shape (env)
  "POST /api/agents/:id/shapes — create a new credential shape. Returns the
   bearer token, server public key, and agent private key once (the server
   keeps only hashes and its own key halves)."
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (if forbidden
        forbidden
        (let ((id (extract-id-from-path (getf env :path-info) "^/api/agents/(\\d+)/shapes$")))
          (let ((denied (owned-agent-error id user-id)))
            (when denied (return-from handle-create-agent-shape denied)))
          (bind ((name (json-assoc :name (parse-json-body env)))
                 ((:values shape-id bearer server-public agent-private)
                  (create-agent-shape id (or name "web"))))
            (json-response `(:id ,shape-id
                             :bearer ,bearer
                             :server_public ,server-public
                             :agent_private ,agent-private
                             :agent_id ,id)
                           201))))))

(defun handle-revoke-agent-shape (env)
  "DELETE /api/agents/:id/shapes/:shape_id"
  (multiple-value-bind (user-id forbidden) (require-session-user env)
    (if forbidden
        forbidden
        (let* ((path (getf env :path-info))
               (id (extract-id-from-path path "^/api/agents/(\\d+)/shapes/\\d+$"))
               (shape-id (extract-id-from-path path "^/api/agents/\\d+/shapes/(\\d+)$")))
          (let ((denied (owned-agent-error id user-id)))
            (when denied (return-from handle-revoke-agent-shape denied)))
          (revoke-agent-shape id shape-id)
          (json-response `(:message "Shape revoked"))))))
