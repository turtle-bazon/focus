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
   :options (list (clingon:make-option :long "status"
                                       :description "Filter by status"
                                       :type :string)
                  (clingon:make-option :long "priority"
                                       :description "Filter by priority"
                                       :type :string))))

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
   :options (list (clingon:make-option :long "title"
                                       :description "Ticket title"
                                       :type :string
                                       :required t)
                  (clingon:make-option :long "description"
                                       :description "Ticket description"
                                       :type :string)
                  (clingon:make-option :long "priority"
                                       :description "Ticket priority"
                                       :type :string
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
   :options (list (clingon:make-option :long "id"
                                       :description "Ticket ID"
                                       :type :integer
                                       :required t)
                  (clingon:make-option :long "status"
                                       :description "New status"
                                       :type :string)
                  (clingon:make-option :long "priority"
                                       :description "New priority"
                                       :type :string))))

(defun make-delete-command ()
  "Create the delete command."
  (clingon:make-command
   :name "delete"
   :description "Delete a ticket"
   :handler (lambda (cmd)
              (bind ((id (clingon:getopt cmd :id)))
                (delete-ticket id)
                (format t "Deleted ticket ~a~%" id)))
   :options (list (clingon:make-option :long "id"
                                       :description "Ticket ID"
                                       :type :integer
                                       :required t))))

(defun make-root-command ()
  "Create the root CLI command."
  (clingon:make-command
   :name "focus"
   :description "Ticket tracker CLI"
   :subcommands (list (make-list-command)
                      (make-create-command)
                      (make-update-command)
                      (make-delete-command))))
