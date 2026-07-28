(in-package :focus)

;;; Activity model

(defun create-activity (ticket-id user-id action &key details)
  "Create a new activity entry. Returns the activity ID."
  (db-query
   "INSERT INTO activity (ticket_id, user_id, action, details) VALUES ($1, $2, $3, $4) RETURNING id"
   ticket-id user-id action (when details (cl-json:encode-json-to-string details))
   :single))

(defun list-activity (ticket-id)
  "List all activity for a ticket."
  (pg-query-params
   "SELECT id, ticket_id, user_id, action, details, created_at
    FROM activity WHERE ticket_id = $1
    ORDER BY created_at DESC"
   (list ticket-id)))

(defun get-activity-by-id (id)
  "Get activity by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, ticket_id, user_id, action, details, created_at
                   FROM activity WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))
