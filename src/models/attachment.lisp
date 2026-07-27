(in-package :focus)

;;; Attachment model

(defun create-attachment (issue-id filename content-type size data)
  "Create a new attachment. Returns the attachment ID."
  (db-query
   "INSERT INTO attachments (issue_id, filename, content_type, size, data)
    VALUES ($1, $2, $3, $4, $5) RETURNING id"
   issue-id filename content-type size data
   :single))

(defun get-attachment-by-id (id)
  "Get attachment by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, issue_id, filename, content_type, size, created_at
                   FROM attachments WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun get-attachment-data (id)
  "Get attachment data (binary). Returns the bytea data."
  (db-query
   "SELECT data FROM attachments WHERE id = $1"
   id :single))

(defun list-attachments (issue-id)
  "List all attachments for an issue."
  (pg-query-params
   "SELECT id, issue_id, filename, content_type, size, created_at
    FROM attachments WHERE issue_id = $1
    ORDER BY created_at ASC"
   (list issue-id)))

(defun delete-attachment (id)
  "Delete attachment by ID."
  (db-execute "DELETE FROM attachments WHERE id = $1" id))
