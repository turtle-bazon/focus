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

;;; Session model — PostgreSQL-backed sessions

(defun create-db-session (session-id user-id expires-at)
  "Create a session in the database."
  (db-execute
   "INSERT INTO sessions (id, user_id, expires_at) VALUES ($1, $2, $3)"
   session-id user-id expires-at))

(defun get-db-session (session-id)
  "Get an active session for a user who has not been deleted. Returns plist or nil."
  (let ((results (db-query
                  "SELECT s.id, s.user_id, s.created_at, s.expires_at
                   FROM sessions s JOIN users u ON u.id = s.user_id
                   WHERE s.id = $1 AND s.expires_at > now() AND u.is_deleted = FALSE"
                  session-id :alists)))
    (when results (alist-to-plist (car results)))))

(defun delete-db-session (session-id)
  "Delete a session from the database."
  (db-execute "DELETE FROM sessions WHERE id = $1" session-id))

(defun delete-expired-sessions ()
  "Delete all expired sessions."
  (db-execute "DELETE FROM sessions WHERE expires_at <= now()"))
