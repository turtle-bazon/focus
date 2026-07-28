(in-package :focus)

;;; Comment model

(defun create-comment (ticket-id user-id body)
  "Create a new comment. Returns the comment ID."
  (db-query
   "INSERT INTO comments (ticket_id, user_id, body) VALUES ($1, $2, $3) RETURNING id"
   ticket-id user-id body
   :single))

(defun get-comment-by-id (id)
  "Get comment by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, ticket_id, user_id, body, created_at, updated_at
                   FROM comments WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-comments (ticket-id)
  "List all comments for a ticket."
  (pg-query-params
   "SELECT id, ticket_id, user_id, body, created_at, updated_at
    FROM comments WHERE ticket_id = $1
    ORDER BY created_at ASC"
   (list ticket-id)))

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
