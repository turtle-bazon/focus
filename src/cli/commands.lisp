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

;;; CLI Commands

(defun make-list-command ()
  "Create the list command."
  (clingon:make-command
   :name "list"
   :description "List tickets"
   :handler (lambda (cmd)
              (bind ((status (clingon:getopt cmd :status))
                     (priority (clingon:getopt cmd :priority))
                     (tickets (list-tickets :status status :priority priority)))
                (iter (for ticket in tickets)
                  (format t "~a | ~a | ~a | ~a~%"
                          (cdr (assoc :id ticket))
                          (cdr (assoc :title ticket))
                          (cdr (assoc :status ticket))
                          (cdr (assoc :priority ticket))))))
   :options (list (clingon:make-option :string
                                       :long-name "status"
                                       :description "Filter by status"
                                       :key :status)
                  (clingon:make-option :string
                                       :long-name "priority"
                                       :description "Filter by priority"
                                       :key :priority))))

(defun make-create-command ()
  "Create the create command."
  (clingon:make-command
   :name "create"
   :description "Create a new ticket"
   :handler (lambda (cmd)
              (bind ((title (clingon:getopt cmd :title))
                     (description (clingon:getopt cmd :description))
                     (priority (clingon:getopt cmd :priority))
                     (id (create-ticket title
                                        :description description
                                        :priority priority)))
                (format t "Created ticket ~a~%" id)))
   :options (list (clingon:make-option :string
                                       :long-name "title"
                                       :description "Ticket title"
                                       :key :title
                                       :required t)
                  (clingon:make-option :string
                                       :long-name "description"
                                       :description "Ticket description"
                                       :key :description)
                  (clingon:make-option :string
                                       :long-name "priority"
                                       :description "Ticket priority"
                                       :key :priority
                                       :initial-value "medium"))))

(defun make-update-command ()
  "Create the update command."
  (clingon:make-command
   :name "update"
   :description "Update a ticket"
   :handler (lambda (cmd)
              (bind ((id (clingon:getopt cmd :id))
                     (status (clingon:getopt cmd :status))
                     (priority (clingon:getopt cmd :priority))
                     (ticket (update-ticket id :status status :priority priority)))
                (if ticket
                    (format t "Updated ticket ~a~%" id)
                    (format t "Ticket not found~%"))))
   :options (list (clingon:make-option :integer
                                       :long-name "id"
                                       :description "Ticket ID"
                                       :key :id
                                       :required t)
                  (clingon:make-option :string
                                       :long-name "status"
                                       :description "New status"
                                       :key :status)
                  (clingon:make-option :string
                                       :long-name "priority"
                                       :description "New priority"
                                       :key :priority))))

(defun make-delete-command ()
  "Create the delete command."
  (clingon:make-command
   :name "delete"
   :description "Delete a ticket"
   :handler (lambda (cmd)
              (bind ((id (clingon:getopt cmd :id)))
                (delete-ticket id)
                (format t "Deleted ticket ~a~%" id)))
   :options (list (clingon:make-option :integer
                                       :long-name "id"
                                       :description "Ticket ID"
                                       :key :id
                                       :required t))))

(defun make-root-command ()
  "Create the root CLI command. With no subcommand it runs the web server."
  (clingon:make-command
   :name "focus"
   :description "Ticket tracker CLI and web server"
   :options (list (clingon:make-option
                   :flag
                   :long-name "rebuild-db"
                   :description "Drop and re-create the database schema"
                   :key :rebuild-db))
   :handler #'start-server
   :sub-commands (list (make-list-command)
                       (make-create-command)
                       (make-update-command)
                       (make-delete-command))))
