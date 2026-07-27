(in-package :focus)

;;; CLI Commands

(defun make-list-command ()
  "Create the list command."
  (clingon:make-command
   :name "list"
   :description "List issues"
   :handler (lambda (cmd)
              (bind ((status (clingon:getopt cmd :status))
                     (priority (clingon:getopt cmd :priority))
                     (issues (list-issues :status status :priority priority)))
                (iter (for issue in issues)
                  (format t "~a | ~a | ~a | ~a~%"
                          (cdr (assoc :id issue))
                          (cdr (assoc :title issue))
                          (cdr (assoc :status issue))
                          (cdr (assoc :priority issue))))))
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
   :description "Create a new issue"
   :handler (lambda (cmd)
              (bind ((title (clingon:getopt cmd :title))
                     (description (clingon:getopt cmd :description))
                     (priority (clingon:getopt cmd :priority))
                     (id (create-issue title
                                      :description description
                                      :priority priority)))
                (format t "Created issue ~a~%" id)))
   :options (list (clingon:make-option :long "title"
                                       :description "Issue title"
                                       :type :string
                                       :required t)
                  (clingon:make-option :long "description"
                                       :description "Issue description"
                                       :type :string)
                  (clingon:make-option :long "priority"
                                       :description "Issue priority"
                                       :type :string
                                       :initial-value "medium"))))

(defun make-update-command ()
  "Create the update command."
  (clingon:make-command
   :name "update"
   :description "Update an issue"
   :handler (lambda (cmd)
              (bind ((id (clingon:getopt cmd :id))
                     (status (clingon:getopt cmd :status))
                     (priority (clingon:getopt cmd :priority))
                     (issue (update-issue id :status status :priority priority)))
                (if issue
                    (format t "Updated issue ~a~%" id)
                    (format t "Issue not found~%"))))
   :options (list (clingon:make-option :long "id"
                                       :description "Issue ID"
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
   :description "Delete an issue"
   :handler (lambda (cmd)
              (bind ((id (clingon:getopt cmd :id)))
                (delete-issue id)
                (format t "Deleted issue ~a~%" id)))
   :options (list (clingon:make-option :long "id"
                                       :description "Issue ID"
                                       :type :integer
                                       :required t))))

(defun make-root-command ()
  "Create the root CLI command."
  (clingon:make-command
   :name "focus"
   :description "Issue tracker CLI"
   :subcommands (list (make-list-command)
                      (make-create-command)
                      (make-update-command)
                      (make-delete-command))))
