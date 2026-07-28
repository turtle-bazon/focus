(in-package :focus)

;;; Session model — PostgreSQL-backed sessions

(defun create-db-session (session-id user-id expires-at)
  "Create a session in the database."
  (db-execute
   "INSERT INTO sessions (id, user_id, expires_at) VALUES ($1, $2, $3)"
   session-id user-id expires-at))

(defun get-db-session (session-id)
  "Get a session from the database. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, user_id, created_at, expires_at FROM sessions WHERE id = $1 AND expires_at > now()"
                  session-id :alists)))
    (when results (alist-to-plist (car results)))))

(defun delete-db-session (session-id)
  "Delete a session from the database."
  (db-execute "DELETE FROM sessions WHERE id = $1" session-id))

(defun delete-expired-sessions ()
  "Delete all expired sessions."
  (db-execute "DELETE FROM sessions WHERE expires_at <= now()"))
