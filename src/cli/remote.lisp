;;; focus-cli — ticket tracker
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

;;; focus-cli — remote REST client. Run it from any machine; it talks to the
;;; server's API with the stored agent API key. No database access.

(define-condition api-error (error)
  ((message :initarg :message :reader api-error-message))
  (:report (lambda (condition stream)
             (format stream "~a" (api-error-message condition)))))

(defun read-all-stream (stream)
  "Read STREAM to end and return the text."
  (let ((out (make-string-output-stream)))
    (iter (for ch = (read-char stream nil nil))
      (while ch)
      (write-char ch out))
    (get-output-stream-string out)))

(defun json-key (key)
  "Normalize a decoded cl-json keyword key (collapse '--' to '-')."
  (normalize-json-key key))

(defun json-> (obj)
  "Decode a cl-json result into plists: objects become plists, arrays lists."
  (cond ((null obj) nil)
        ((and (listp obj) (consp (car obj)))
         (if (consp (caar obj))
             (mapcar #'json-> obj)
             (let ((plist nil))
               (iter (for (key . val) in obj)
                 (setf plist (list* (json-key key) (list* (json-> val) plist))))
               plist)))
        ((listp obj) (mapcar #'json-> obj))
        (t obj)))

(defun url-encode (str)
  "Percent-encode STR for use in a query string."
  (with-output-to-string (out)
    (iter (for ch in-string str)
      (if (alphanumericp ch)
          (write-char ch out)
          (format out "%~2,'0X" (char-code ch))))))

(defun build-query (params)
  "Build a query string from a plist of PARAMS, skipping NIL values."
  (let ((parts nil))
    (iter (for (key val) on params by #'cddr)
      (when val
        (push (format nil "~a=~a"
                      (substitute #\_ #\- (string-downcase (symbol-name key)))
                      (url-encode (princ-to-string val)))
              parts)))
    (unless (null parts)
      (format nil "~{~a~^&~}" (nreverse parts)))))

(defun api-call (method path &key query body)
  "Call the API at the configured server. Returns decoded plist(s) or errors."
  (let* ((server (cli-config-get :server-url))
         (key (cli-config-get :key))
         (url (format nil "~a~a~@[?~a~]" server path query)))
    (unless server
      (error 'api-error :message (format nil "No server configured. Run: focus-cli configure --server URL~%")))
    (unless key
      (error 'api-error :message (format nil "No API key configured. Run: focus-cli configure --key KEY~%")))
    (handler-case
        (progn
          (multiple-value-bind (resp status)
              (dexador:request url :method method :bearer-auth key
                               :content (when body
                                          (cl-json:encode-json-to-string (plist-to-json body)))
                               :want-stream t)
            (let ((decoded (let ((text (read-all-stream resp)))
                             (when (and text (plusp (length text)))
                               (json-> (cl-json:decode-json-from-string text))))))
              (if (<= 200 status 299)
                  decoded
                  (error 'api-error :message (or (getf decoded :error)
                                                 (format nil "HTTP ~a" status)))))))
      (api-error (e) (error e))
      (dexador.error:http-request-failed (e)
        (let* ((body (response-body e))
               (msg (when (and body (plusp (length body)))
                      (handler-case
                          (let ((decoded (json-> (cl-json:decode-json-from-string body))))
                            (or (getf decoded :error) body))
                        (error () body)))))
          (error 'api-error
                 :message (or msg
                              (when (response-status e)
                                (format nil "HTTP ~a" (response-status e)))
                              (princ-to-string e)))))
      (error (e)
        (error 'api-error :message (princ-to-string e))))))

(defmacro with-api-errors (&body body)
  "Run BODY, printing any api-error and continuing."
  `(handler-case (progn ,@body)
     (api-error (e)
       (format t "Error: ~a~%" (api-error-message e)))))

(defun print-ticket-list-remote (tickets json?)
  "Print a list of ticket plists."
  (if json?
      (cli-json `(:tickets ,tickets :count ,(length tickets)))
      (iter (for ticket in tickets)
        (format t "~a | ~a | ~a | ~a~%"
                (getf ticket :id)
                (getf ticket :title)
                (getf ticket :status)
                (getf ticket :priority)))))

(defun remote-labels (ticket-id)
  "Fetch labels for TICKET-ID via the API."
  (getf (api-call :get (format nil "/api/tickets/~a/labels" ticket-id)) :labels))

(defun remote-show-ticket (ticket json?)
  "Print TICKET with its labels and comments."
  (let* ((labels (remote-labels (getf ticket :id)))
         (result (api-call :get (format nil "/api/tickets/~a/comments" (getf ticket :id))))
         (comments (getf result :comments)))
    (if json?
        (cli-json `(:ticket ,ticket :labels ,labels :comments ,comments))
        (progn
          (format t "Ticket ~a: ~a~%" (getf ticket :id) (getf ticket :title))
          (format t "  Status: ~a | Priority: ~a~%"
                  (getf ticket :status) (getf ticket :priority))
          (when (getf ticket :description)
            (format t "  ~a~%" (getf ticket :description)))
          (format t "  Labels: ~{~a~^, ~}~%"
                  (iter (for label in labels) (collecting (getf label :name))))
          (format t "  Comments:~%")
          (iter (for comment in comments)
            (format t "    [#~a] ~a~%" (getf comment :id) (getf comment :body)))))))

(defun make-remote-configure-command ()
  "Create the configure command."
  (clingon:make-command
   :name "configure"
   :description "Store the server URL and agent API key in ~/.focus-cli"
   :handler (lambda (cmd)
              (let ((config (read-cli-config)))
                (write-cli-config
                 (list :server-url (or (clingon:getopt cmd :server) (getf config :server-url))
                       :key (or (clingon:getopt cmd :key) (getf config :key))
                       :agent-id (or (clingon:getopt cmd :agent) (getf config :agent-id))
                       :board-id (or (clingon:getopt cmd :board) (getf config :board-id))))
                (format t "Configured. Run 'focus-cli status' to review.~%")))
   :options (list (clingon:make-option :string
                                       :long-name "server"
                                       :description "Server base URL, e.g. http://host:8080"
                                       :key :server)
                  (clingon:make-option :string
                                       :long-name "key"
                                       :description "Agent API key (focusN-...)"
                                       :key :key)
                  (clingon:make-option :integer
                                       :long-name "agent"
                                       :description "Agent ID"
                                       :key :agent)
                  (clingon:make-option :integer
                                       :long-name "board"
                                       :description "Default board ID"
                                       :key :board))))

(defun make-remote-status-command ()
  "Create the status command."
  (clingon:make-command
   :name "status"
   :description "Show stored server, agent, board, and key"
   :handler (lambda (cmd)
              (declare (ignore cmd))
              (let ((config (read-cli-config)))
                (if config
                    (progn
                      (format t "Server: ~a~%" (or (getf config :server-url) "-"))
                      (format t "Agent:  ~a~%" (or (getf config :agent-id) "-"))
                      (format t "Board:  ~a~%" (or (getf config :board-id) "-"))
                      (format t "Key:    ~a~%" (mask-key (getf config :key))))
                    (format t "Not configured. Run: focus-cli configure --server URL --key KEY~%"))))
   :options nil))

(defun make-remote-list-command ()
  "Create the list command."
  (clingon:make-command
   :name "list"
   :description "List tickets (defaults to the stored board)"
   :handler (lambda (cmd)
              (with-api-errors
                (let* ((status (clingon:getopt cmd :status))
                       (priority (clingon:getopt cmd :priority))
                       (assignee (clingon:getopt cmd :assignee))
                       (board (or (clingon:getopt cmd :board) (cli-default-board-id)))
                       (limit (clingon:getopt cmd :limit))
                       (page (clingon:getopt cmd :page))
                       (search (clingon:getopt cmd :search))
                       (json? (clingon:getopt cmd :json)))
                  (if search
                      (print-ticket-list-remote
                       (getf (api-call :get "/api/tickets/search"
                                       :query (build-query `(:q ,search)))
                             :tickets)
                       json?)
                      (print-ticket-list-remote
                       (getf (api-call :get "/api/tickets"
                                       :query (build-query `(:status ,status
                                                                :priority ,priority
                                                                :assignee-id ,assignee
                                                                :board-id ,board
                                                                :limit ,limit
                                                                :page ,page)))
                             :tickets)
                       json?)))))
   :options (list (clingon:make-option :string :long-name "status"
                                       :description "Filter by status" :key :status)
                  (clingon:make-option :string :long-name "priority"
                                       :description "Filter by priority" :key :priority)
                  (clingon:make-option :integer :long-name "assignee"
                                       :description "Filter by assignee ID" :key :assignee)
                  (clingon:make-option :integer :long-name "board"
                                       :description "Board ID" :key :board)
                  (clingon:make-option :integer :long-name "limit"
                                       :description "Max tickets to show" :key :limit
                                       :initial-value 20)
                  (clingon:make-option :integer :long-name "page"
                                       :description "Page number" :key :page
                                       :initial-value 1)
                  (clingon:make-option :string :long-name "search"
                                       :description "Full-text search query" :key :search)
                  (clingon:make-option :flag :long-name "json"
                                       :description "Output as JSON" :key :json))))

(defun make-remote-show-command ()
  "Create the show command."
  (clingon:make-command
   :name "show"
   :description "Show ticket details, labels, and comments"
   :handler (lambda (cmd)
              (with-api-errors
                (let* ((id (cli-int-arg cmd 0))
                       (ticket (when id (api-call :get (format nil "/api/tickets/~a" id)))))
                  (if ticket
                      (remote-show-ticket ticket (clingon:getopt cmd :json))
                      (format t "Ticket not found~%")))))
   :options (list (clingon:make-option :flag :long-name "json"
                                       :description "Output as JSON" :key :json))))

(defun make-remote-create-command ()
  "Create the create command."
  (clingon:make-command
   :name "create"
   :description "Create a new ticket (defaults to the stored board)"
   :handler (lambda (cmd)
              (with-api-errors
                (let* ((title (clingon:getopt cmd :title))
                       (board (or (clingon:getopt cmd :board) (cli-default-board-id)))
                       (result (api-call :post "/api/tickets"
                                         :body `(:title ,title
                                                  :board-id ,board
                                                  :description ,(clingon:getopt cmd :description)
                                                  :status ,(clingon:getopt cmd :status)
                                                  :priority ,(clingon:getopt cmd :priority)
                                                  :assignee-id ,(clingon:getopt cmd :assignee)
                                                  :color ,(clingon:getopt cmd :color)))))
                  (format t "Created ticket ~a~%" (getf result :id)))))
   :options (list (clingon:make-option :string :long-name "title"
                                       :description "Ticket title" :key :title :required t)
                  (clingon:make-option :string :long-name "description"
                                       :description "Ticket description" :key :description)
                  (clingon:make-option :string :long-name "priority"
                                       :description "Ticket priority" :key :priority
                                       :initial-value "medium")
                  (clingon:make-option :string :long-name "status"
                                       :description "Ticket status" :key :status
                                       :initial-value "open")
                  (clingon:make-option :integer :long-name "board"
                                       :description "Board ID" :key :board)
                  (clingon:make-option :integer :long-name "assignee"
                                       :description "Assignee ID" :key :assignee)
                  (clingon:make-option :string :long-name "color"
                                       :description "Card color" :key :color))))

(defun make-remote-update-command ()
  "Create the update command."
  (clingon:make-command
   :name "update"
   :description "Update a ticket"
   :handler (lambda (cmd)
              (with-api-errors
                (let* ((id (cli-int-arg cmd 0))
                       (result (when id
                                 (api-call :put (format nil "/api/tickets/~a" id)
                                           :body `(:title ,(clingon:getopt cmd :title)
                                                    :description ,(clingon:getopt cmd :description)
                                                    :status ,(clingon:getopt cmd :status)
                                                    :priority ,(clingon:getopt cmd :priority)
                                                    :assignee-id ,(clingon:getopt cmd :assignee)
                                                    :color ,(clingon:getopt cmd :color))))))
                  (if result
                      (format t "Updated ticket ~a~%" id)
                      (format t "Ticket not found~%")))))
   :options (list (clingon:make-option :string :long-name "title"
                                       :description "New title" :key :title)
                  (clingon:make-option :string :long-name "description"
                                       :description "New description" :key :description)
                  (clingon:make-option :string :long-name "status"
                                       :description "New status" :key :status)
                  (clingon:make-option :string :long-name "priority"
                                       :description "New priority" :key :priority)
                  (clingon:make-option :integer :long-name "assignee"
                                       :description "New assignee ID" :key :assignee)
                  (clingon:make-option :string :long-name "color"
                                       :description "New card color" :key :color))))

(defun make-remote-delete-command ()
  "Create the delete command."
  (clingon:make-command
   :name "delete"
   :description "Delete a ticket"
   :handler (lambda (cmd)
              (with-api-errors
                (let ((id (cli-int-arg cmd 0)))
                  (if id
                      (progn
                        (api-call :delete (format nil "/api/tickets/~a" id))
                        (format t "Deleted ticket ~a~%" id))
                      (format t "Missing ticket ID~%")))))
   :options nil))

(defun make-remote-comment-add-command ()
  "Create the comment add command."
  (clingon:make-command
   :name "add"
   :description "Add a comment to a ticket (as the stored agent)"
   :handler (lambda (cmd)
              (with-api-errors
                (let* ((ticket (cli-int-arg cmd 0))
                       (body (clingon:getopt cmd :body))
                       (result (when (and ticket body)
                                 (api-call :post (format nil "/api/tickets/~a/comments" ticket)
                                           :body `(:body ,body)))))
                  (if result
                      (format t "Added comment ~a to ticket ~a~%" (getf result :id) ticket)
                      (format t "Usage: focus-cli comment add TICKET --body TEXT~%")))))
   :options (list (clingon:make-option :string :long-name "body"
                                       :description "Comment text" :key :body :required t))))

(defun make-remote-comment-list-command ()
  "Create the comment list command."
  (clingon:make-command
   :name "list"
   :description "List comments on a ticket"
   :handler (lambda (cmd)
              (with-api-errors
                (let ((ticket (cli-int-arg cmd 0)))
                  (if ticket
                      (iter (for comment in (getf (api-call :get
                                                            (format nil "/api/tickets/~a/comments" ticket))
                                                  :comments))
                        (format t "~a | ~a~%" (getf comment :id) (getf comment :body)))
                      (format t "Missing ticket ID~%")))))
   :options nil))

(defun make-remote-comment-delete-command ()
  "Create the comment delete command."
  (clingon:make-command
   :name "delete"
   :description "Delete a comment from a ticket"
   :handler (lambda (cmd)
              (with-api-errors
                (let ((ticket (cli-int-arg cmd 0))
                      (comment (cli-int-arg cmd 1)))
                  (if (and ticket comment)
                      (progn
                        (api-call :delete (format nil "/api/tickets/~a/comments/~a" ticket comment))
                        (format t "Deleted comment ~a from ticket ~a~%" comment ticket))
                      (format t "Usage: focus-cli comment delete TICKET COMMENT~%")))))
   :options nil))

(defun make-remote-comment-command ()
  "Create the comment command group."
  (clingon:make-command
   :name "comment"
   :description "Manage ticket comments"
   :sub-commands (list (make-remote-comment-add-command)
                       (make-remote-comment-list-command)
                       (make-remote-comment-delete-command))))

(defun make-remote-label-list-command ()
  "Create the label list command."
  (clingon:make-command
   :name "list"
   :description "List all labels"
   :handler (lambda (cmd)
              (declare (ignore cmd))
              (with-api-errors
                (iter (for label in (getf (api-call :get "/api/labels") :labels))
                  (format t "~a | ~a | ~a~%"
                          (getf label :id)
                          (getf label :name)
                          (getf label :color)))))
   :options nil))

(defun make-remote-label-tag-command (name description post)
  "Create a shared label add/remove command by NAME."
  (clingon:make-command
   :name name
   :description description
   :handler (lambda (cmd)
              (with-api-errors
                (let ((ticket (cli-int-arg cmd 0))
                      (label (cli-int-arg cmd 1)))
                  (if (and ticket label)
                      (progn
                        (api-call (if post :post :delete)
                                  (format nil "/api/tickets/~a/labels/~a" ticket label))
                        (format t "~a label ~a ~a ticket ~a~%"
                                (if post "Added" "Removed") label (if post "to" "from") ticket))
                      (format t "Usage: focus-cli label ~a TICKET LABEL~%" name)))))
   :options nil))

(defun make-remote-label-command ()
  "Create the label command group."
  (clingon:make-command
   :name "label"
   :description "Manage labels"
   :sub-commands (list (make-remote-label-list-command)
                       (make-remote-label-tag-command "add" "Add a label to a ticket" t)
                       (make-remote-label-tag-command "remove" "Remove a label from a ticket" nil))))

(defun make-remote-board-list-command ()
  "Create the board list command."
  (clingon:make-command
   :name "list"
   :description "List boards visible to the agent"
   :handler (lambda (cmd)
              (declare (ignore cmd))
              (with-api-errors
                (iter (for board in (getf (api-call :get "/api/boards") :boards))
                  (format t "~a | ~a | ~a~%"
                          (getf board :id)
                          (getf board :name)
                          (getf board :type)))))
   :options nil))

(defun make-remote-board-command ()
  "Create the board command group."
  (clingon:make-command
   :name "board"
   :description "Boards visible to the agent"
   :sub-commands (list (make-remote-board-list-command))))

(defun make-remote-root-command ()
  "Create the focus-cli root command."
  (clingon:make-command
   :name "focus-cli"
   :description "Remote command-line client for the Focus ticket server"
   :handler (lambda (cmd)
              (declare (ignore cmd))
              (format t "No subcommand given. See 'focus-cli --help'.~%"))
   :sub-commands (list (make-remote-configure-command)
                       (make-remote-status-command)
                       (make-remote-list-command)
                       (make-remote-show-command)
                       (make-remote-create-command)
                       (make-remote-update-command)
                       (make-remote-delete-command)
                       (make-remote-comment-command)
                       (make-remote-label-command)
                       (make-remote-board-command))))

(defun remote-main ()
  "Entry point for the focus-cli binary."
  (clingon:run (make-remote-root-command)))