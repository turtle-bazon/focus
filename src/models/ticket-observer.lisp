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

;;; Ticket observer model

(defun add-ticket-observer (ticket-id observer-type observer-id)
  "Add an observer (user or group) to a ticket."
  (db-query
   "INSERT INTO ticket_observers (ticket_id, observer_type, observer_id)
    VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"
   ticket-id observer-type observer-id))

(defun remove-ticket-observer (ticket-id observer-type observer-id)
  "Remove an observer from a ticket."
  (db-query
   "DELETE FROM ticket_observers
    WHERE ticket_id = $1 AND observer_type = $2 AND observer_id = $3"
   ticket-id observer-type observer-id))

(defun list-ticket-observers (ticket-id)
  "List all observers for a ticket."
  (pg-query-params
   "SELECT observer_type, observer_id FROM ticket_observers WHERE ticket_id = $1"
   (list ticket-id)))

(defun count-ticket-observers (ticket-id)
  "Count observers for a ticket."
  (let ((result (db-query
                 "SELECT COUNT(*) as count FROM ticket_observers WHERE ticket_id = $1"
                 ticket-id :single)))
    (or result 0)))
