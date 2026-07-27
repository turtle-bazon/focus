(in-package :focus)

;;; Activity model

(defun create-activity (issue-id user-id action &key details)
  "Create a new activity entry. Returns the activity ID."
  (db-query
   "INSERT INTO activity (issue_id, user_id, action, details) VALUES ($1, $2, $3, $4) RETURNING id"
   issue-id user-id action (when details (cl-json:encode-json-to-string details))
   :single))

(defun list-activity (issue-id)
  "List all activity for an issue."
  (pg-query-params
   "SELECT id, issue_id, user_id, action, details, created_at
    FROM activity WHERE issue_id = $1
    ORDER BY created_at DESC"
   (list issue-id)))

(defun get-activity-by-id (id)
  "Get activity by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, issue_id, user_id, action, details, created_at
                   FROM activity WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))
