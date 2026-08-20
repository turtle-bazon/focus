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

;;; Ticket model

(defun get-default-board-id ()
  "ID of the default board everyone sees, or nil."
  (db-query "SELECT id FROM boards WHERE is_default LIMIT 1" :single))

(defun create-ticket (title &key description status priority assignee-id assignee-type color board-id)
  "Create a new ticket. Returns the ticket ID."
  (let ((status (or status "open"))
        (assignee-type (or assignee-type "user"))
        (board-id (or board-id (get-default-board-id))))
    (db-query
     "INSERT INTO tickets (title, description, status, priority, assignee_id, assignee_type, color, board_id, position_num, position_den)
       VALUES ($1, $2, $3::varchar, $4, NULLIF($5, 0), $6, $7, $8,
               COALESCE((SELECT MAX(position_num) + 1 FROM tickets WHERE status = $3::varchar), 0),
               1)
       RETURNING id"
     title
     (sql-null-or description)
     status
     (or priority "medium")
     (or assignee-id 0)
     assignee-type
     (or color "#6b7280")
     board-id
     :single)))

(defun get-ticket-by-id (id)
  "Get ticket by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, title, description, status, priority, assignee_id, assignee_type, color,
                          board_id, position_num, position_den, created_at, updated_at
                   FROM tickets WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-tickets (&key status priority assignee-id board-id (page 1) (limit 20))
  "List tickets with optional filters. Returns list of plists."
  (let ((page (max 1 (or page 1)))
        (limit (or limit 20))
        (conditions '())
        (params '()))
    (when status
      (push "(status = $1)" conditions)
      (push status params))
    (when priority
      (push (format nil "(priority = $~d)" (+ 1 (length params))) conditions)
      (push priority params))
    (when assignee-id
      (push (format nil "(assignee_id = $~d)" (+ 1 (length params))) conditions)
      (push assignee-id params))
    (when board-id
      (push (format nil "(board_id = $~d)" (+ 1 (length params))) conditions)
      (push board-id params))
    (let ((where (if conditions
                     (format nil "WHERE ~{~a~^ AND ~}" (reverse conditions))
                     ""))
          (all-params (append (reverse params)
                             (list limit (* (- page 1) limit)))))
      (pg-query-params
       (format nil "SELECT id, title, description, status, priority, assignee_id, assignee_type, color,
                           board_id, position_num, position_den, created_at, updated_at
                    FROM tickets ~a
                    ORDER BY CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 ELSE 1 END,
                             (position_num::float / position_den) ASC, created_at DESC
                    LIMIT $~d OFFSET $~d"
               where
               (+ 1 (length params))
               (+ 2 (length params)))
       all-params))))

(defun count-tickets (&key status priority assignee-id board-id)
  "Count tickets matching optional filters. Returns integer."
  (let ((conditions '())
        (params '()))
    (when status
      (push "status = $1" conditions)
      (push status params))
    (when priority
      (push (format nil "priority = $~d" (+ 1 (length params))) conditions)
      (push priority params))
    (when assignee-id
      (push (format nil "assignee_id = $~d" (+ 1 (length params))) conditions)
      (push assignee-id params))
    (when board-id
      (push (format nil "board_id = $~d" (+ 1 (length params))) conditions)
      (push board-id params))
    (let ((where (if conditions
                    (format nil "WHERE ~{~a~^ AND ~}" (reverse conditions))
                    "")))
      (let ((rows (pg-query-params
                   (format nil "SELECT COUNT(*) AS total FROM tickets ~a" where)
                   (reverse params))))
        (or (getf (car rows) :total) 0)))))

(defun run-dynamic-update (table assignments id &key (extra ""))
  "Run UPDATE TABLE SET col = $1, ... WHERE id = $n for ASSIGNMENTS, an alist
   of (column-name . value) pairs; only non-nil values are assigned. ID is
   bound as the last parameter; EXTRA is appended verbatim after the SET list
   (e.g. \", updated_at = NOW()\"). Returns the query rows."
  (when assignments
    (let* ((count (length assignments))
           (sets (iter (for i from 1 to count)
                       (for (col . nil) in assignments)
                       (collecting (format nil "~a = $~d" col i))))
           (params (append (mapcar #'cdr assignments) (list id))))
      (pg-query-params
       (format nil "UPDATE ~a SET ~{~a~^, ~}~a WHERE id = $~d"
               table sets extra (1+ count))
       params))))

(defun ticket-update-assignments (title description status priority assignee-id assignee-type color board-id)
  "Alist of supplied ticket columns for a partial update."
  (remove-if (lambda (pair) (null (cdr pair)))
             (list (cons "title" title)
                   (cons "description" description)
                   (cons "status" status)
                   (cons "priority" priority)
                   (cons "assignee_id" assignee-id)
                   (cons "assignee_type" assignee-type)
                   (cons "color" color)
                   (cons "board_id" board-id))))

(defun update-ticket (id &key title description status priority assignee-id assignee-type color board-id)
  "Update ticket fields. Returns the updated ticket."
  (run-dynamic-update
   "tickets"
   (ticket-update-assignments title description status priority
                              assignee-id assignee-type color board-id)
   id
   :extra ", updated_at = NOW()")
  (get-ticket-by-id id))

(defconstant +compression-threshold+ 1000
  "Compress fractional positions when denominator exceeds this.")

(defun compress-positions (ticket-ids)
  "Reassign contiguous integer positions to a list of ticket IDs."
  (iter (for idx from 0)
        (for ticket-id in ticket-ids)
        (db-execute
         "UPDATE tickets SET position_num = $1, position_den = 1 WHERE id = $2"
         idx ticket-id)))

(defun group-neighbors (board-id status priority exclude-id)
  "Tickets in the group ordered by fractional position, excluding EXCLUDE-ID."
  (pg-query-params
   "SELECT id, position_num, position_den
    FROM tickets WHERE status = $1 AND priority = $2 AND id != $3 AND board_id = $4
    ORDER BY (position_num::float / position_den) ASC, created_at DESC"
   (list status priority exclude-id board-id)))

(defun neighbor-position (before after)
  "Compute the fractional position (values num den) between the BEFORE and
   AFTER neighbor plists (either may be nil). The mediant of a/b and c/d lies
   strictly between them; sentinels handle a missing neighbor."
  (cond
    ((and before after)
     (values (+ (getf before :position_num) (getf after :position_num))
             (+ (getf before :position_den) (getf after :position_den))))
    (before
     (values (+ (getf before :position_num) (getf before :position_den))
             (getf before :position_den)))
    (after
     (values (getf after :position_num) (1+ (getf after :position_den))))
    (t (values 0 1))))

(defun compress-group-if-needed (new-den board-id status priority)
  "Reassign contiguous positions when denominators grow too large."
  (when (> new-den +compression-threshold+)
    (let ((all-ids (mapcar (lambda (plist) (getf plist :id))
                           (pg-query-params
                            "SELECT id FROM tickets WHERE status = $1 AND priority = $2 AND board_id = $3
                             ORDER BY (position_num::float / position_den) ASC, created_at DESC"
                            (list status priority board-id)))))
      (compress-positions all-ids))))

(defun reposition-ticket (id new-status new-priority new-position)
  "Move a ticket using fractional indexing. Only updates the moved ticket.
   Compresses the group when denominators grow too large."
  (let* ((board-id (getf (get-ticket-by-id id) :board-id))
         (pos (max 0 (min new-position 10000)))
         ;; Move ticket to target group, then find its neighbors there.
         (neighbors (progn
                      (db-execute
                       "UPDATE tickets SET status = $1, priority = $2, updated_at = NOW() WHERE id = $3"
                       new-status new-priority id)
                      (group-neighbors board-id new-status new-priority id)))
         (before (when (and (plusp pos) (>= (length neighbors) pos))
                   (elt neighbors (1- pos))))
         (after (when (< pos (length neighbors))
                  (elt neighbors pos))))
    (multiple-value-bind (new-num new-den) (neighbor-position before after)
      (db-execute
       "UPDATE tickets SET position_num = $1, position_den = $2, updated_at = NOW() WHERE id = $3"
       new-num new-den id)
      (compress-group-if-needed new-den board-id new-status new-priority)))
  (get-ticket-by-id id))

(defun delete-ticket (id)
  "Delete ticket by ID."
  (db-execute "DELETE FROM tickets WHERE id = $1" id))

(defun search-tickets (search-query)
  "Full-text search tickets by title and description."
  (pg-query-params
   "SELECT id, title, description, status, priority, assignee_id, assignee_type, color,
           board_id, position_num, position_den, created_at, updated_at
    FROM tickets
    WHERE title ILIKE $1 OR description ILIKE $1
    ORDER BY CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 ELSE 1 END,
             (position_num::float / position_den) ASC, created_at DESC"
   (list (format nil "%~a%" search-query))))
