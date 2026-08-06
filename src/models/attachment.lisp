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

;;; Attachment model

(defun create-attachment (ticket-id filename content-type size data)
  "Create a new attachment. Returns the attachment ID."
  (db-query
   "INSERT INTO attachments (ticket_id, filename, content_type, size, data)
    VALUES ($1, $2, $3, $4, $5) RETURNING id"
   ticket-id filename content-type size data
   :single))

(defun get-attachment-by-id (id)
  "Get attachment by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, ticket_id, filename, content_type, size, created_at
                   FROM attachments WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun get-attachment-data (id)
  "Get attachment data (binary). Returns the bytea data."
  (db-query
   "SELECT data FROM attachments WHERE id = $1"
   id :single))

(defun list-attachments (ticket-id)
  "List all attachments for a ticket."
  (pg-query-params
   "SELECT id, ticket_id, filename, content_type, size, created_at
    FROM attachments WHERE ticket_id = $1
    ORDER BY created_at ASC"
   (list ticket-id)))

(defun delete-attachment (id)
  "Delete attachment by ID."
  (db-execute "DELETE FROM attachments WHERE id = $1" id))
