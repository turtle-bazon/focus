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

;;; Webhook model

(defun events-to-sql-array (events)
  "Convert list of event strings to PostgreSQL array literal."
  (when events
    (format nil "{~{~s~^,~}}" events)))

(defun sql-array-to-list (array-str)
  "Convert PostgreSQL array literal to list of strings."
  (when array-str
    (let ((trimmed (string-trim "{}" array-str)))
      (when (> (length trimmed) 0)
        (split-sequence:split-sequence #\, trimmed)))))

(defun create-webhook (url &key secret events active)
  "Create a new webhook. Returns the webhook ID."
  (db-query
   "INSERT INTO webhooks (url, secret, events, active)
    VALUES ($1, $2, $3::text[], $4) RETURNING id"
   url
   secret
   (events-to-sql-array events)
   (if (null active) t active)
   :single))

(defun get-webhook-by-id (id)
  "Get webhook by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, url, secret, events, active, created_at
                   FROM webhooks WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-webhooks ()
  "List all webhooks."
  (pg-query-params
   "SELECT id, url, secret, events, active, created_at
    FROM webhooks ORDER BY created_at DESC"
   nil))

(defun update-webhook (id &key url secret events active)
  "Update webhook fields. Returns the updated webhook."
  (when (or url secret events active)
    (db-execute
     "UPDATE webhooks SET
        url = COALESCE($1, url),
        secret = COALESCE($2, secret),
        events = COALESCE($3::text[], events),
        active = COALESCE($4, active)
      WHERE id = $5"
     url
     secret
     (events-to-sql-array events)
     active
     id))
  (get-webhook-by-id id))

(defun delete-webhook (id)
  "Delete webhook by ID."
  (db-execute "DELETE FROM webhooks WHERE id = $1" id))
