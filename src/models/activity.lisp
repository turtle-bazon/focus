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

;;; Activity model

(defun json-escape-string (str)
  "Escape a string for JSON."
  (with-output-to-string (s)
    (iter (for i from 0 below (length str))
      (let ((ch (char str i)))
        (case ch
          (#\" (write-string "\\\"" s))
          (#\\ (write-string "\\\\" s))
          (#\Newline (write-string "\\n" s))
          (#\Return (write-string "\\r" s))
          (#\Tab (write-string "\\t" s))
          (otherwise (write-char ch s)))))))

(defun details-to-json (details)
  "Convert an alist to a JSON object string."
  (when details
    (let ((pairs (iter (for (key . val) in details)
                    (collect (format nil "\"~a\":~a"
                                    (if (symbolp key)
                                        (string-downcase (symbol-name key))
                                        key)
                                    (etypecase val
                                      (string (format nil "\"~a\"" (json-escape-string val)))
                                      (integer (format nil "~a" val))
                                      (null "null")))))))
      (format nil "{~{~a~^,~}}" pairs))))

(defun create-activity (ticket-id user-id action &key details)
  "Create a new activity entry. Returns the activity ID."
  (db-query
   "INSERT INTO activity (ticket_id, user_id, action, details) VALUES ($1, $2, $3, $4) RETURNING id"
   ticket-id user-id action (details-to-json details)
   :single))

(defun list-activity (ticket-id &key (limit 20) (offset 0))
  "List activity for a ticket with pagination."
  (pg-query-params
   "SELECT id, ticket_id, user_id, action, details, created_at
    FROM activity WHERE ticket_id = $1
    ORDER BY created_at DESC
    LIMIT $2 OFFSET $3"
   (list ticket-id limit offset)))

(defun count-activity (ticket-id)
  "Count total activity entries for a ticket."
  (let ((result (pg-query-params
                 "SELECT COUNT(*) as count FROM activity WHERE ticket_id = $1"
                 (list ticket-id))))
    (when result
      (getf (car result) :count))))

(defun list-board-activity (board-id &key (limit 20) (offset 0))
  "List activity for all tickets on a board with pagination. Returns rows
   including the ticket title and status for context."
  (pg-query-params
   "SELECT a.id, a.ticket_id, a.user_id, a.action, a.details, a.created_at,
           t.title AS ticket_title, t.status AS ticket_status
    FROM activity a
    JOIN tickets t ON t.id = a.ticket_id
    WHERE t.board_id = $1
    ORDER BY a.created_at DESC
    LIMIT $2 OFFSET $3"
   (list board-id limit offset)))

(defun count-board-activity (board-id)
  "Count total activity entries for all tickets on a board."
  (let ((result (pg-query-params
                 "SELECT COUNT(a.id) AS count
                  FROM activity a
                  JOIN tickets t ON t.id = a.ticket_id
                  WHERE t.board_id = $1"
                 (list board-id))))
    (when result
      (getf (car result) :count))))

(defun list-all-board-activity (user-id &key (limit 20) (offset 0))
  "List activity for tickets USER-ID is involved with (is assignee/owner or
   observer, directly or via one of their groups) on boards they can see,
   newest first. Rows include board and ticket context. NIL matches nothing."
  (if (null user-id)
      nil
      (pg-query-params
       "SELECT a.id, a.ticket_id, a.user_id, a.action, a.details, a.created_at,
               b.id AS board_id, b.name AS board_name,
               t.title AS ticket_title, t.status AS ticket_status
        FROM activity a
        JOIN tickets t ON t.id = a.ticket_id
        JOIN boards b ON b.id = t.board_id
        WHERE b.id IN (
          SELECT DISTINCT v.id FROM boards v
          LEFT JOIN board_members vm ON vm.board_id = v.id
          LEFT JOIN group_members vg ON vg.group_id = vm.member_id
            AND vm.member_type = 'group'
          WHERE v.is_default
             OR v.owner_id = $1
             OR (vm.member_type = 'user' AND vm.member_id = $1)
             OR vg.user_id = $1)
          AND (
            (t.assignee_type = 'user' AND t.assignee_id = $1)
            OR (t.assignee_type = 'group' AND t.assignee_id IN
                (SELECT gm.group_id FROM group_members gm WHERE gm.user_id = $1))
            OR EXISTS (
              SELECT 1 FROM ticket_observers obs
              WHERE obs.ticket_id = t.id
                AND ((obs.observer_type = 'user' AND obs.observer_id = $1)
                     OR (obs.observer_type = 'group' AND obs.observer_id IN
                         (SELECT gm.group_id FROM group_members gm WHERE gm.user_id = $1))))
          )
        ORDER BY a.created_at DESC
        LIMIT $2 OFFSET $3"
       (list user-id limit offset))))

(defun count-all-board-activity (user-id)
  "Count activity rows for tickets USER-ID is involved with, across all
   boards they can see."
  (if (null user-id)
      0
      (let ((result (pg-query-params
                     "SELECT COUNT(a.id) AS count
                      FROM activity a
                      JOIN tickets t ON t.id = a.ticket_id
                      WHERE t.board_id IN (
                        SELECT DISTINCT v.id FROM boards v
                        LEFT JOIN board_members vm ON vm.board_id = v.id
                        LEFT JOIN group_members vg ON vg.group_id = vm.member_id
                          AND vm.member_type = 'group'
                        WHERE v.is_default
                           OR v.owner_id = $1
                           OR (vm.member_type = 'user' AND vm.member_id = $1)
                           OR vg.user_id = $1)
                        AND (
                          (t.assignee_type = 'user' AND t.assignee_id = $1)
                          OR (t.assignee_type = 'group' AND t.assignee_id IN
                              (SELECT gm.group_id FROM group_members gm WHERE gm.user_id = $1))
                          OR EXISTS (
                            SELECT 1 FROM ticket_observers obs
                            WHERE obs.ticket_id = t.id
                              AND ((obs.observer_type = 'user' AND obs.observer_id = $1)
                                   OR (obs.observer_type = 'group' AND obs.observer_id IN
                                       (SELECT gm.group_id FROM group_members gm WHERE gm.user_id = $1))))
                        )"
                     (list user-id))))
        (when result
          (getf (car result) :count)))))

(defun get-activity-by-id (id)
  "Get activity by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, ticket_id, user_id, action, details, created_at
                   FROM activity WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun get-activity-with-context (id)
  "Get activity by ID joined with its ticket and board for live delivery.
   Returns plist or nil."
  (let ((results (pg-query-params
                  "SELECT a.id, a.ticket_id, a.user_id, a.action, a.details,
                          a.created_at, t.title AS ticket_title,
                          t.status AS ticket_status, b.id AS board_id,
                          b.name AS board_name
                   FROM activity a
                   JOIN tickets t ON t.id = a.ticket_id
                   JOIN boards b ON b.id = t.board_id
                   WHERE a.id = $1"
                  (list id))))
    (when results (car results))))
