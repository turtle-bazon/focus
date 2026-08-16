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

;;; Comment model

(defun create-comment (ticket-id user-id body &key agent-id)
  "Create a new comment. Returns the comment ID."
  (db-query
   "INSERT INTO comments (ticket_id, user_id, agent_id, body) VALUES ($1, $2, $3, $4) RETURNING id"
   ticket-id (sql-null-or user-id) (sql-null-or agent-id) body
   :single))

(defun get-comment-by-id (id)
  "Get comment by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, ticket_id, user_id, agent_id, body, created_at, updated_at
                   FROM comments WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun count-comments (ticket-id)
  "Count total comments for a ticket."
  (let ((result (pg-query-params
                 "SELECT COUNT(*) as count FROM comments WHERE ticket_id = $1"
                 (list ticket-id))))
    (when result
      (getf (car result) :count))))

(defun list-comments (ticket-id &key (limit 50) (offset 0))
  "List comments for a ticket with pagination."
  (pg-query-params
   "SELECT id, ticket_id, user_id, agent_id, body, created_at, updated_at
    FROM comments WHERE ticket_id = $1
    ORDER BY created_at DESC
    LIMIT $2 OFFSET $3"
   (list ticket-id limit offset)))

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
