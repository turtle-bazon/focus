(in-package :focus)

;;; User model

(defun create-user (username email)
  "Create a new user. Returns the user ID."
  (db-query
   "INSERT INTO users (username, email) VALUES ($1, $2) RETURNING id"
   username email :single))

(defun get-user-by-id (id)
  "Get user by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, username, email, created_at FROM users WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun get-user-by-username (username)
  "Get user by username. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, username, email, created_at FROM users WHERE username = $1"
                  username :alists)))
    (when results (alist-to-plist (car results)))))

(defun get-user-by-email (email)
  "Get user by email. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, username, email, created_at FROM users WHERE email = $1"
                  email :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-users ()
  "List all users. Returns list of plists."
  (pg-query-params
   "SELECT id, username, email, created_at FROM users ORDER BY username"
   nil))

(defun update-user (id &key username email)
  "Update user fields. Returns the updated user."
  (when (or username email)
    (db-execute
     "UPDATE users SET username = COALESCE($1, username), email = COALESCE($2, email) WHERE id = $3"
     username email id))
  (get-user-by-id id))

(defun delete-user (id)
  "Delete user by ID."
  (db-execute "DELETE FROM users WHERE id = $1" id))
