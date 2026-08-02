(in-package :focus)

;;; User model

(defun create-user (username email &key picture)
  "Create a new user. Returns the new user ID."
  (bl:info "create-user called: username=~a email=~a picture=~a" username email picture)
  (let ((id (db-query
             "INSERT INTO users (username, email, picture, role) VALUES ($1, $2, $3, 'user') RETURNING id"
             username email picture :single)))
    (bl:info "create-user inserted id=~a" id)
    id))

(defun get-user-by-id (id)
  "Get user by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, username, email, picture, role, created_at FROM users WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun get-user-by-username (username)
  "Get user by username. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, username, email, picture, role, created_at FROM users WHERE username = $1"
                  username :alists)))
    (when results (alist-to-plist (car results)))))

(defun get-user-by-email (email)
  "Get user by email. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, username, email, picture, role, created_at FROM users WHERE email = $1"
                  email :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-users ()
  "List all users. Returns list of plists."
  (pg-query-params
   "SELECT id, username, email, picture, role, created_at FROM users ORDER BY username"
   nil))

(defun update-user (id &key username email picture role)
  "Update user fields. Returns the updated user."
  (let ((sets nil)
        (params nil)
        (idx 0))
    (when username
      (incf idx)
      (push (format nil "username = $~a" idx) sets)
      (push username params))
    (when email
      (incf idx)
      (push (format nil "email = $~a" idx) sets)
      (push email params))
    (when picture
      (incf idx)
      (push (format nil "picture = $~a" idx) sets)
      (push picture params))
    (when role
      (incf idx)
      (push (format nil "role = $~a" idx) sets)
      (push role params))
    (when sets
      (incf idx)
      (let ((sql (format nil "UPDATE users SET ~{~a~^, ~} WHERE id = $~a"
                          (reverse sets) idx)))
        (pg-query-params sql (append (reverse params) (list id))))))
  (get-user-by-id id))

(defun delete-user (id)
  "Delete user by ID."
  ;; Unassign tickets assigned to this user
  (db-execute "UPDATE tickets SET assignee_id = NULL WHERE assignee_id = $1" id)
  ;; Detach comments and activity (keep history, drop the user link)
  (db-execute "UPDATE comments SET user_id = NULL WHERE user_id = $1" id)
  (db-execute "UPDATE activity SET user_id = NULL WHERE user_id = $1" id)
  ;; Remove from ticket observers
  (db-execute "DELETE FROM ticket_observers WHERE observer_type = 'user' AND observer_id = $1" id)
  ;; Sessions and group_members cascade automatically
  (db-execute "DELETE FROM users WHERE id = $1" id))
