(in-package :focus)

;;; User model

(defun create-user (username email &key picture)
  "Create a new user. Returns the user plist."
  (bl:info "create-user called: username=~a email=~a picture=~a" username email picture)
  (let ((id (db-query
             "INSERT INTO users (username, email, picture) VALUES ($1, $2, $3) RETURNING id"
             username email picture :single)))
    (bl:info "create-user inserted id=~a" id)
    (get-user-by-id id)))

(defun get-user-by-id (id)
  "Get user by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, username, email, picture, created_at FROM users WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun get-user-by-username (username)
  "Get user by username. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, username, email, picture, created_at FROM users WHERE username = $1"
                  username :alists)))
    (when results (alist-to-plist (car results)))))

(defun get-user-by-email (email)
  "Get user by email. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, username, email, picture, created_at FROM users WHERE email = $1"
                  email :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-users ()
  "List all users. Returns list of plists."
  (pg-query-params
   "SELECT id, username, email, picture, created_at FROM users ORDER BY username"
   nil))

(defun update-user (id &key username email picture)
  "Update user fields. Returns the updated user."
  (when (or username email picture)
    (db-execute
     "UPDATE users SET username = COALESCE($1, username), email = COALESCE($2, email), picture = COALESCE($3, picture) WHERE id = $4"
     username email picture id))
  (get-user-by-id id))

(defun delete-user (id)
  "Delete user by ID."
  (db-execute "DELETE FROM users WHERE id = $1" id))
