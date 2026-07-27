(in-package :focus)

;;; Comment model

(defun create-comment (issue-id user-id body)
  "Create a new comment. Returns the comment ID."
  (db-query
   "INSERT INTO comments (issue_id, user_id, body) VALUES ($1, $2, $3) RETURNING id"
   issue-id user-id body
   :single))

(defun get-comment-by-id (id)
  "Get comment by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, issue_id, user_id, body, created_at, updated_at
                   FROM comments WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-comments (issue-id)
  "List all comments for an issue."
  (pg-query-params
   "SELECT id, issue_id, user_id, body, created_at, updated_at
    FROM comments WHERE issue_id = $1
    ORDER BY created_at ASC"
   (list issue-id)))

(defun update-comment (id &key body)
  "Update comment body. Returns the updated comment."
  (when body
    (db-execute
     "UPDATE comments SET body = $1, updated_at = NOW() WHERE id = $2"
     body id))
  (get-comment-by-id id))

(defun delete-comment (id)
  "Delete comment by ID."
  (db-execute "DELETE FROM comments WHERE id = $1" id))
