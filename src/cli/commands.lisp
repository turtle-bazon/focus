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

(defmacro with-cli-db (&body body)
  "Connect to the database from the config file, run BODY, then disconnect.
   Reuses an already-open top-level connection."
  `(let ((had-connection (and postmodern:*database*
                             (postmodern:connected-p postmodern:*database*))))
     (unless had-connection
       (connect-db (read-config (find-config))))
     (unwind-protect (progn ,@body)
       (unless had-connection
         (postmodern:disconnect-toplevel)))))

(defun cli-args (cmd)
  "Free positional arguments parsed by clingon for CMD."
  (clingon:command-arguments cmd))

(defun cli-int-arg (cmd index)
  "Parse the INDEX-th positional argument of CMD as an integer, or nil."
  (let ((raw (nth index (cli-args cmd))))
    (when raw (parse-integer (string raw) :junk-allowed t))))

(defun cli-json (data)
  "Print DATA as a single JSON line."
  (format t "~a~%" (cl-json:encode-json-to-string (plist-to-json data))))

;;; Compact clingon option constructors

(defun opt-string (long-name description key &key required initial-value)
  "A clingon string option."
  (clingon:make-option :string
                       :long-name long-name
                       :description description
                       :key key
                       :required required
                       :initial-value initial-value))

(defun opt-int (long-name description key &key required initial-value)
  "A clingon integer option."
  (clingon:make-option :integer
                       :long-name long-name
                       :description description
                       :key key
                       :required required
                       :initial-value initial-value))

(defun opt-flag (long-name description key)
  "A clingon boolean flag option."
  (clingon:make-option :flag
                       :long-name long-name
                       :description description
                       :key key))

(defparameter +focus-cli-config-path+
  (merge-pathnames #P".focus-cli" (user-homedir-pathname)))

(defun read-cli-config ()
  "Read the CLI config, or NIL. Returns (:sites ((NAME . PLIST) ...)).
  A legacy bare-plist file, or an old (:current ...) file, is normalized."
  (when (probe-file +focus-cli-config-path+)
    (handler-case
        (let ((data (with-open-file (stream +focus-cli-config-path+)
                      (read stream nil))))
          (cond ((and (consp data) (eq (car data) :sites)) data)
                ((and (consp data) (eq (car data) :current))
                 (list :sites (getf data :sites)))
                (t (list :sites (list (cons "default" data))))))
      (error () nil))))

(defun cli-site-config (site)
  "The plist of the named SITE, or NIL."
  (cdr (assoc site (getf (read-cli-config) :sites) :test #'string=)))

(defun write-cli-config-file (config)
  "Persist the full CONFIG structure."
  (with-open-file (stream +focus-cli-config-path+
                          :direction :output :if-exists :supersede)
    (prin1 config stream)))

(defun store-site-config (config site)
  "Persist CONFIG merged over SITE's current values, keeping other sites.
  Returns the merged plist."
  (let* ((loaded (read-cli-config))
         (sites (getf loaded :sites))
         (others (remove site sites :key #'car :test #'string=))
         (merged (append config (cli-site-config site))))
    (write-cli-config-file
     (list :sites (cons (cons site merged) others)))
    merged))

(defun write-cli-config (config &optional (site "default"))
  "Persist CONFIG into SITE (merged over existing keys), keeping other sites."
  (store-site-config config site)
  (format t "Saved agent identity to ~a~%" +focus-cli-config-path+))

(defun cli-site-names ()
  "Names of all configured sites."
  (iter (for site in (getf (read-cli-config) :sites))
    (collecting (car site))))

(defun split-board-spec (spec)
  "Split a SITE/BOARD spec into (values BOARD SITE); SITE is NIL when absent."
  (let ((slash (position #\/ spec :from-end t)))
    (if slash
        (values (subseq spec (1+ slash))
                (subseq spec 0 slash))
        (values spec nil))))

(defun cli-site-boards (site)
  "Alist of stored (local-name . remote-name) board aliases for SITE."
  (getf (cli-site-config site) :boards))

(defun cli-local-board-remote (site local)
  "The remote board name that LOCAL aliases in SITE, or NIL."
  (cdr (assoc local (cli-site-boards site) :test #'string-equal)))

(defun cli-set-site-board (site local remote)
  "Record LOCAL -> REMOTE board alias in SITE, deduplicated by local name.
  Silent."
  (let* ((current (cli-site-boards site))
         (boards (remove local current :key #'car :test #'string-equal)))
    (store-site-config (list :boards (cons (cons local remote) boards)) site)))

(defun cli-add-site (name url bearer server-public agent-private)
  "Add or update SITE with its server URL and agent shape credentials,
   keeping existing boards."
  (let* ((old (cli-site-config name))
         (sites (remove name (getf (read-cli-config) :sites)
                        :key #'car :test #'string=)))
    (write-cli-config-file
     (list :sites
           (cons (cons name
                       (list :server-url url
                             :bearer bearer
                             :server-public server-public
                             :agent-private agent-private
                             :boards (getf old :boards)))
                 sites)))
    (format t "Added site ~a. Add boards: focus-cli add-board --site ~a~%"
            name name)))

(defun cli-config-get (key)
  "Look up KEY in the default site's config (used by the local 'focus' CLI)."
  (getf (cli-site-config "default") key))

(defun cli-default-agent-id ()
  "The stored agent ID, or NIL."
  (cli-config-get :agent-id))

(defun cli-default-board-id ()
  "The stored board ID, or NIL."
  (cli-config-get :board-id))

(defun mask-key (token)
  "Mask an API key for display, e.g. 'focus3-abcd...ef01'."
  (cond ((and token (> (length token) 14))
         (concatenate 'string (subseq token 0 11) "..."
                      (subseq token (- (length token) 4))))
        (token "•••")
        (t "-")))

(defun print-ticket-list (tickets json?)
  "Print TICKETS as rows or JSON."
  (if json?
      (cli-json `(:tickets ,tickets :count ,(length tickets)))
      (iter (for ticket in tickets)
        (format t "~a | ~a | ~a | ~a~%"
                (getf ticket :id)
                (getf ticket :title)
                (getf ticket :status)
                (getf ticket :priority)))))

(defun print-ticket-detail (ticket json?)
  "Print TICKET with its labels and comments."
  (let ((labels (get-ticket-labels (getf ticket :id)))
        (comments (list-comments (getf ticket :id))))
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

(defun cli-list-handler (cmd)
  "Handler for the local list command."
  (with-cli-db
    (bind ((status (clingon:getopt cmd :status))
           (priority (clingon:getopt cmd :priority))
           (assignee (clingon:getopt cmd :assignee))
           (board (or (clingon:getopt cmd :board) (cli-default-board-id)))
           (limit (clingon:getopt cmd :limit))
           (page (clingon:getopt cmd :page))
           (search (clingon:getopt cmd :search))
           (json? (clingon:getopt cmd :json)))
      (if search
          (print-ticket-list (search-tickets search) json?)
          (print-ticket-list (list-tickets :status status
                                           :priority priority
                                           :assignee-id assignee
                                           :board-id board
                                           :limit limit
                                           :page page)
                             json?)))))

(defun make-list-command ()
  "Create the list command."
  (clingon:make-command
   :name "list"
   :description "List tickets"
   :handler #'cli-list-handler
   :options (list (opt-string "status" "Filter by status" :status)
                  (opt-string "priority" "Filter by priority" :priority)
                  (opt-int "assignee" "Filter by assignee ID" :assignee)
                  (opt-int "board" "Filter by board ID" :board)
                  (opt-int "limit" "Max tickets to show" :limit :initial-value 20)
                  (opt-int "page" "Page number" :page :initial-value 1)
                  (opt-string "search" "Full-text search query" :search)
                  (opt-flag "json" "Output as JSON" :json))))

(defun make-show-command ()
  "Create the show command."
  (clingon:make-command
   :name "show"
   :description "Show ticket details, labels, and comments"
   :handler (lambda (cmd)
              (with-cli-db
                (let* ((id (cli-int-arg cmd 0))
                       (ticket (when id (get-ticket-by-id id))))
                  (if ticket
                      (print-ticket-detail ticket (clingon:getopt cmd :json))
                      (format t "Ticket not found~%")))))
   :options (list (clingon:make-option :flag
                                       :long-name "json"
                                       :description "Output as JSON"
                                       :key :json))))

(defun cli-create-handler (cmd)
  "Handler for the local create command."
  (with-cli-db
    (bind ((title (clingon:getopt cmd :title))
           (description (clingon:getopt cmd :description))
           (priority (clingon:getopt cmd :priority))
           (status (clingon:getopt cmd :status))
           (board (or (clingon:getopt cmd :board) (cli-default-board-id)))
           (assignee (clingon:getopt cmd :assignee))
           (color (clingon:getopt cmd :color)))
      (let ((id (create-ticket title
                               :description description
                               :priority priority
                               :status status
                               :board-id board
                               :assignee-id assignee
                               :color color)))
        (format t "Created ticket ~a~%" id)))))

(defun make-create-command ()
  "Create the create command."
  (clingon:make-command
   :name "create"
   :description "Create a new ticket"
   :handler #'cli-create-handler
   :options (list (opt-string "title" "Ticket title" :title :required t)
                  (opt-string "description" "Ticket description" :description)
                  (opt-string "priority" "Ticket priority" :priority :initial-value "medium")
                  (opt-string "status" "Ticket status" :status :initial-value "open")
                  (opt-int "board" "Board ID" :board)
                  (opt-int "assignee" "Assignee ID" :assignee)
                  (opt-string "color" "Card color" :color))))

(defun cli-update-handler (cmd)
  "Handler for the local update command."
  (with-cli-db
    (let* ((id (cli-int-arg cmd 0))
           (ticket (when id
                     (update-ticket id
                                    :title (clingon:getopt cmd :title)
                                    :description (clingon:getopt cmd :description)
                                    :status (clingon:getopt cmd :status)
                                    :priority (clingon:getopt cmd :priority)
                                    :assignee-id (clingon:getopt cmd :assignee)
                                    :board-id (clingon:getopt cmd :board)
                                    :color (clingon:getopt cmd :color)))))
      (if ticket
          (format t "Updated ticket ~a~%" id)
          (format t "Ticket not found~%")))))

(defun make-update-command ()
  "Create the update command."
  (clingon:make-command
   :name "update"
   :description "Update a ticket"
   :handler #'cli-update-handler
   :options (list (opt-string "title" "New title" :title)
                  (opt-string "description" "New description" :description)
                  (opt-string "status" "New status" :status)
                  (opt-string "priority" "New priority" :priority)
                  (opt-int "assignee" "New assignee ID" :assignee)
                  (opt-int "board" "New board ID" :board)
                  (opt-string "color" "New card color" :color))))

(defun make-delete-command ()
  "Create the delete command."
  (clingon:make-command
   :name "delete"
   :description "Delete a ticket"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((id (cli-int-arg cmd 0)))
                  (if id
                      (progn
                        (delete-ticket id)
                        (format t "Deleted ticket ~a~%" id))
                      (format t "Missing ticket ID~%")))))
   :options nil))

(defun make-comment-add-command ()
  "Create the comment add command."
  (clingon:make-command
   :name "add"
   :description "Add a comment to a ticket"
   :handler (lambda (cmd)
              (with-cli-db
                (bind ((ticket (cli-int-arg cmd 0))
                       (body (clingon:getopt cmd :body))
                       (user (clingon:getopt cmd :user))
                       (agent (if (clingon:getopt cmd :user)
                                  nil
                                  (or (clingon:getopt cmd :agent) (cli-default-agent-id)))))
                  (cond ((null ticket)
                         (format t "Missing ticket ID~%"))
                        ((and user agent)
                         (format t "Specify only one of --user or --agent~%"))
                        ((or user agent)
                         (let ((id (create-comment ticket user body :agent-id agent)))
                           (format t "Added comment ~a to ticket ~a~%" id ticket)))
                        (t
                         (format t "No authoring identity. Run 'focus agent init', or specify --user/--agent~%"))))))
   :options (list (clingon:make-option :string
                                       :long-name "body"
                                       :description "Comment text"
                                       :key :body
                                       :required t)
                  (clingon:make-option :integer
                                       :long-name "user"
                                       :description "Authoring user ID"
                                       :key :user)
                  (clingon:make-option :integer
                                       :long-name "agent"
                                       :description "Authoring agent ID"
                                       :key :agent))))

(defun make-comment-list-command ()
  "Create the comment list command."
  (clingon:make-command
   :name "list"
   :description "List comments on a ticket"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((ticket (cli-int-arg cmd 0)))
                  (if ticket
                      (iter (for comment in (list-comments ticket))
                        (format t "~a | ~a~%" (getf comment :id) (getf comment :body)))
                      (format t "Missing ticket ID~%")))))
   :options nil))

(defun make-comment-delete-command ()
  "Create the comment delete command."
  (clingon:make-command
   :name "delete"
   :description "Delete a comment"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((id (cli-int-arg cmd 0)))
                  (if id
                      (progn
                        (delete-comment id)
                        (format t "Deleted comment ~a~%" id))
                      (format t "Missing comment ID~%")))))
   :options nil))

(defun make-comment-command ()
  "Create the comment command group."
  (clingon:make-command
   :name "comment"
   :description "Manage ticket comments"
   :sub-commands (list (make-comment-add-command)
                       (make-comment-list-command)
                       (make-comment-delete-command))))

(defun make-label-list-command ()
  "Create the label list command."
  (clingon:make-command
   :name "list"
   :description "List all labels"
   :handler (lambda (cmd)
              (declare (ignore cmd))
              (with-cli-db
                (iter (for label in (list-labels))
                  (format t "~a | ~a | ~a~%"
                          (getf label :id)
                          (getf label :name)
                          (getf label :color)))))
   :options nil))

(defun make-label-create-command ()
  "Create the label create command."
  (clingon:make-command
   :name "create"
   :description "Create a new label"
   :handler (lambda (cmd)
              (with-cli-db
                (bind ((name (clingon:getopt cmd :name))
                       (color (clingon:getopt cmd :color)))
                  (let ((id (create-label name :color color)))
                    (format t "Created label ~a~%" id)))))
   :options (list (clingon:make-option :string
                                       :long-name "name"
                                       :description "Label name"
                                       :key :name
                                       :required t)
                  (clingon:make-option :string
                                       :long-name "color"
                                       :description "Label color"
                                       :key :color))))

(defun make-label-add-command ()
  "Create the label add command."
  (clingon:make-command
   :name "add"
   :description "Add a label to a ticket"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((ticket (cli-int-arg cmd 0))
                      (label (cli-int-arg cmd 1)))
                  (if (and ticket label)
                      (progn
                        (add-label-to-ticket ticket label)
                        (format t "Added label ~a to ticket ~a~%" label ticket))
                      (format t "Usage: focus label add TICKET LABEL~%")))))
   :options nil))

(defun make-label-remove-command ()
  "Create the label remove command."
  (clingon:make-command
   :name "remove"
   :description "Remove a label from a ticket"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((ticket (cli-int-arg cmd 0))
                      (label (cli-int-arg cmd 1)))
                  (if (and ticket label)
                      (progn
                        (remove-label-from-ticket ticket label)
                        (format t "Removed label ~a from ticket ~a~%" label ticket))
                      (format t "Usage: focus label remove TICKET LABEL~%")))))
   :options nil))

(defun make-label-command ()
  "Create the label command group."
  (clingon:make-command
   :name "label"
   :description "Manage labels"
   :sub-commands (list (make-label-list-command)
                       (make-label-create-command)
                       (make-label-add-command)
                       (make-label-remove-command))))

(defun make-user-list-command ()
  "Create the user list command."
  (clingon:make-command
   :name "list"
   :description "List users"
   :handler (lambda (cmd)
              (declare (ignore cmd))
              (with-cli-db
                (iter (for user in (list-users))
                  (format t "~a | ~a | ~a | ~a~%"
                          (getf user :id)
                          (getf user :username)
                          (getf user :email)
                          (getf user :role)))))
   :options nil))

(defun make-user-command ()
  "Create the user command group."
  (clingon:make-command
   :name "user"
   :description "Manage users"
   :sub-commands (list (make-user-list-command))))

(defun print-agent-shape-secrets (agent-id bearer server-public agent-private)
  "Print shape credentials once — they cannot be recovered later."
  (format t "Shape credentials for agent ~a (store them now, shown once):~%"
          agent-id)
  (format t "  bearer:        ~a~%" bearer)
  (format t "  server-public: ~a~%" server-public)
  (format t "  agent-private: ~a~%" agent-private))

(defun make-agent-create-command ()
  "Create the agent create command."
  (clingon:make-command
   :name "create"
   :description "Create an agent owned by a user"
   :handler (lambda (cmd)
              (with-cli-db
                (bind ((name (clingon:getopt cmd :name))
                       (owner (clingon:getopt cmd :owner))
                       (description (clingon:getopt cmd :description))
                       (with-shape? (clingon:getopt cmd :shape)))
                  (if (and name owner)
                      (let ((id (create-agent owner name :description description)))
                        (format t "Created agent ~a~%" id)
                        (when with-shape?
                          (multiple-value-bind (shape-id bearer server-public agent-private)
                              (create-agent-shape id (or name "cli"))
                            (declare (ignore shape-id))
                            (print-agent-shape-secrets id bearer server-public agent-private))))
                      (format t "Specify --name and --owner~%")))))
   :options (list (clingon:make-option :string
                                        :long-name "name"
                                        :description "Agent name"
                                        :key :name
                                        :required t)
                  (clingon:make-option :integer
                                        :long-name "owner"
                                        :description "Owning user ID"
                                        :key :owner
                                        :required t)
                  (clingon:make-option :string
                                        :long-name "description"
                                        :description "Agent description"
                                        :key :description)
                  (clingon:make-option :flag
                                        :long-name "shape"
                                        :description "Also generate a credential shape"
                                        :key :shape))))

(defun make-agent-list-command ()
  "Create the agent list command."
  (clingon:make-command
   :name "list"
   :description "List agents"
   :handler (lambda (cmd)
              (with-cli-db
                (iter (for agent in (list-agents :owner-id (clingon:getopt cmd :owner)))
                  (format t "~a | ~a | ~a~%"
                          (getf agent :id)
                          (getf agent :owner_id)
                          (getf agent :name)))))
   :options (list (clingon:make-option :integer
                                       :long-name "owner"
                                       :description "Filter by owner user ID"
                                       :key :owner))))

(defun make-agent-delete-command ()
  "Create the agent delete command."
  (clingon:make-command
   :name "delete"
   :description "Delete an agent"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((id (cli-int-arg cmd 0)))
                  (if id
                      (progn
                        (delete-agent id)
                        (format t "Deleted agent ~a~%" id))
                      (format t "Missing agent ID~%")))))
   :options nil))

(defun make-agent-shape-add-command ()
  "Create the agent shape add command."
  (clingon:make-command
   :name "add"
   :description "Generate a new credential shape for an agent (shown once)"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((id (cli-int-arg cmd 0)))
                  (if id
                      (multiple-value-bind (shape-id bearer server-public agent-private)
                          (create-agent-shape id (or (clingon:getopt cmd :name) "cli"))
                        (declare (ignore shape-id))
                        (print-agent-shape-secrets id bearer server-public agent-private))
                      (format t "Missing agent ID~%")))))
   :options (list (clingon:make-option :string
                                        :long-name "name"
                                        :description "Shape name"
                                        :key :name))))

(defun make-agent-shape-list-command ()
  "Create the agent shape list command."
  (clingon:make-command
   :name "list"
   :description "List credential shapes for an agent"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((id (cli-int-arg cmd 0)))
                  (if id
                      (iter (for shape in (list-agent-shapes id))
                        (format t "~a | ~a | ~a | ~a~%"
                                (getf shape :id)
                                (getf shape :name)
                                (getf shape :token_prefix)
                                (if (getf shape :revoked) "revoked" "active")))
                      (format t "Missing agent ID~%")))))
   :options nil))

(defun make-agent-shape-revoke-command ()
  "Create the agent shape revoke command."
  (clingon:make-command
   :name "revoke"
   :description "Revoke an agent credential shape"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((agent (cli-int-arg cmd 0))
                      (shape-id (cli-int-arg cmd 1)))
                  (if (and agent shape-id)
                      (progn
                        (revoke-agent-shape agent shape-id)
                        (format t "Revoked shape ~a for agent ~a~%" shape-id agent))
                      (format t "Usage: focus agent shape revoke AGENT SHAPE-ID~%")))))
   :options nil))

(defun make-agent-shape-command ()
  "Create the agent shape command group."
  (clingon:make-command
   :name "shape"
   :description "Manage agent credential shapes"
   :sub-commands (list (make-agent-shape-add-command)
                       (make-agent-shape-list-command)
                       (make-agent-shape-revoke-command))))

(defun make-agent-use-command ()
  "Create the agent use command."
  (clingon:make-command
   :name "use"
   :description "Adopt an existing agent (and board) created via the web UI"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((agent (clingon:getopt cmd :agent))
                      (board (clingon:getopt cmd :board)))
                  (cond ((null agent)
                         (format t "Specify --agent~%"))
                        ((null (get-agent-by-id agent))
                         (format t "Agent ~a not found~%" agent))
                        ((and board (null (get-board-by-id board)))
                         (format t "Board ~a not found~%" board))
                        (t
                         (let ((config (cli-site-config "default")))
                           (write-cli-config (list :agent-id agent
                                                   :board-id (or board (getf config :board-id))))
                           (format t "Agent identity updated. Run 'focus status' to review.~%")))))))
   :options (list (clingon:make-option :integer
                                        :long-name "agent"
                                        :description "Agent ID to use"
                                        :key :agent
                                        :required t)
                  (clingon:make-option :integer
                                        :long-name "board"
                                        :description "Board ID to work in"
                                        :key :board))))

(defun agent-init-identity (owner name description config)
  "Return (values agent-id bearer server-public agent-private) for the init
   flow, creating the agent and its first credential shape when missing."
  (let ((agent-id (getf config :agent-id))
        (bearer (getf config :bearer))
        (server-public (getf config :server-public))
        (agent-private (getf config :agent-private)))
    (unless (and agent-id (get-agent-by-id agent-id))
      (setf agent-id
            (create-agent owner (or name "CLI Agent") :description description))
      (format t "Created agent ~a~%" agent-id))
    (unless bearer
      (multiple-value-bind (shape-id new-bearer new-server-public new-agent-private)
          (create-agent-shape agent-id (or name "cli"))
        (declare (ignore shape-id))
        (setf bearer new-bearer
              server-public new-server-public
              agent-private new-agent-private)
        (print-agent-shape-secrets agent-id bearer server-public agent-private)))
    (values agent-id bearer server-public agent-private)))

(defun agent-init-board (owner board-name type board-id agent-id)
  "Return a usable BOARD-ID, creating and sharing a new board when asked."
  (unless (and board-id (get-board-by-id board-id))
    (when board-name
      (setf board-id (create-board board-name (or type "common") owner))
      (ensure-board-member board-id "agent" agent-id)
      (format t "Created board ~a: ~a~%" board-id board-name)))
  board-id)

(defun cli-agent-init-handler (cmd)
  "Handler for the local agent init command."
  (with-cli-db
    (let ((owner (clingon:getopt cmd :owner)))
      (if (null owner)
          (format t "Specify --owner~%")
          (let* ((config (cli-site-config "default")))
            (multiple-value-bind (agent-id bearer server-public agent-private)
                (agent-init-identity owner
                                     (clingon:getopt cmd :name)
                                     (clingon:getopt cmd :description)
                                     config)
              (let ((board-id (agent-init-board owner
                                                (clingon:getopt cmd :board)
                                                (clingon:getopt cmd :type)
                                                (getf config :board-id)
                                                agent-id)))
                (write-cli-config (list :agent-id agent-id
                                        :bearer bearer
                                        :server-public server-public
                                        :agent-private agent-private
                                        :board-id board-id))
                (format t "Agent identity stored. Run 'focus status' to review.~%"))))))))

(defun make-agent-init-command ()
  "Create the agent init command."
  (clingon:make-command
   :name "init"
   :description "Create an agent with a board for work and a credential shape, store the identity"
   :handler #'cli-agent-init-handler
   :options (list (opt-int "owner" "Owning user ID" :owner :required t)
                  (opt-string "name" "Agent name" :name)
                  (opt-string "description" "Agent description" :description)
                  (opt-string "board" "Name of a new board to create for work" :board)
                  (opt-string "type" "Board type: common or personal" :type
                              :initial-value "common"))))

(defun make-agent-command ()
  "Create the agent command group."
  (clingon:make-command
   :name "agent"
   :description "Manage agents"
   :sub-commands (list (make-agent-init-command)
                       (make-agent-use-command)
                       (make-agent-create-command)
                       (make-agent-list-command)
                       (make-agent-delete-command)
                       (make-agent-shape-command))))

(defun make-board-create-command ()
  "Create the board create command."
  (clingon:make-command
   :name "create"
   :description "Create a new board"
   :handler (lambda (cmd)
              (with-cli-db
                (bind ((name (clingon:getopt cmd :name))
                       (type (clingon:getopt cmd :type))
                       (owner (clingon:getopt cmd :owner)))
                  (if name
                      (let ((id (create-board name (or type "personal") owner)))
                        (format t "Created board ~a: ~a~%" id name))
                      (format t "Specify --name~%")))))
   :options (list (clingon:make-option :string
                                       :long-name "name"
                                       :description "Board name"
                                       :key :name
                                       :required t)
                  (clingon:make-option :string
                                       :long-name "type"
                                       :description "Board type: personal or common"
                                       :key :type
                                       :initial-value "personal")
                  (clingon:make-option :integer
                                       :long-name "owner"
                                       :description "Owning user ID"
                                       :key :owner))))

(defun make-board-list-command ()
  "Create the board list command."
  (clingon:make-command
   :name "list"
   :description "List all boards"
   :handler (lambda (cmd)
              (declare (ignore cmd))
              (with-cli-db
                (iter (for board in (list-all-boards))
                  (format t "~a | ~a | ~a | ~a~%"
                          (getf board :id)
                          (getf board :name)
                          (getf board :type)
                          (if (getf board :is_default) "default" "")))))
   :options nil))

(defun make-board-delete-command ()
  "Create the board delete command."
  (clingon:make-command
   :name "delete"
   :description "Delete a board"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((id (cli-int-arg cmd 0)))
                  (if id
                      (progn
                        (delete-board id)
                        (format t "Deleted board ~a~%" id))
                      (format t "Missing board ID~%")))))
   :options nil))

(defun make-board-members-command ()
  "Create the board members command."
  (clingon:make-command
   :name "members"
   :description "List members of a board"
   :handler (lambda (cmd)
              (with-cli-db
                (let ((id (cli-int-arg cmd 0)))
                  (if id
                      (iter (for member in (list-board-members id))
                        (format t "~a | ~a | ~a~%"
                                (getf member :member_type)
                                (getf member :member_id)
                                (getf member :name)))
                      (format t "Missing board ID~%")))))
   :options nil))

(defun make-board-member-add-command ()
  "Create the board member add command."
  (clingon:make-command
   :name "add"
   :description "Add a member (agent, user, or group) to a board"
   :handler (lambda (cmd)
              (with-cli-db
                (bind ((board (cli-int-arg cmd 0))
                       (agent (clingon:getopt cmd :agent))
                       (user (clingon:getopt cmd :user))
                       (group (clingon:getopt cmd :group)))
                  (cond ((null board)
                         (format t "Missing board ID~%"))
                        ((> (count-if (function identity) (list agent user group)) 1)
                         (format t "Specify exactly one of --agent, --user, or --group~%"))
                        (agent
                         (ensure-board-member board "agent" agent)
                         (format t "Added agent ~a to board ~a~%" agent board))
                        (user
                         (ensure-board-member board "user" user)
                         (format t "Added user ~a to board ~a~%" user board))
                        (group
                         (ensure-board-member board "group" group)
                         (format t "Added group ~a to board ~a~%" group board))
                        (t
                         (format t "Specify --agent, --user, or --group~%"))))))
   :options (list (clingon:make-option :integer
                                       :long-name "agent"
                                       :description "Agent ID to add"
                                       :key :agent)
                  (clingon:make-option :integer
                                       :long-name "user"
                                       :description "User ID to add"
                                       :key :user)
                  (clingon:make-option :integer
                                       :long-name "group"
                                       :description "Group ID to add"
                                       :key :group))))

(defun make-board-member-remove-command ()
  "Create the board member remove command."
  (clingon:make-command
   :name "remove"
   :description "Remove a member (agent, user, or group) from a board"
   :handler (lambda (cmd)
              (with-cli-db
                (bind ((board (cli-int-arg cmd 0))
                       (agent (clingon:getopt cmd :agent))
                       (user (clingon:getopt cmd :user))
                       (group (clingon:getopt cmd :group)))
                  (cond ((null board)
                         (format t "Missing board ID~%"))
                        ((> (count-if (function identity) (list agent user group)) 1)
                         (format t "Specify exactly one of --agent, --user, or --group~%"))
                        (t
                         (let ((member-type (cond (agent "agent") (user "user") (group "group"))))
                           (if member-type
                               (progn
                                 (remove-board-member board member-type (or agent user group))
                                 (format t "Removed ~a ~a from board ~a~%"
                                         member-type (or agent user group) board))
                               (format t "Specify --agent, --user, or --group~%"))))))))
   :options (list (clingon:make-option :integer
                                       :long-name "agent"
                                       :description "Agent ID to remove"
                                       :key :agent)
                  (clingon:make-option :integer
                                       :long-name "user"
                                       :description "User ID to remove"
                                       :key :user)
                  (clingon:make-option :integer
                                       :long-name "group"
                                       :description "Group ID to remove"
                                       :key :group))))

(defun make-board-member-command ()
  "Create the board member command group."
  (clingon:make-command
   :name "member"
   :description "Manage board members"
   :sub-commands (list (make-board-member-add-command)
                       (make-board-member-remove-command))))

(defun make-board-command ()
  "Create the board command group."
  (clingon:make-command
   :name "board"
   :description "Manage boards"
   :sub-commands (list (make-board-create-command)
                       (make-board-list-command)
                       (make-board-delete-command)
                       (make-board-members-command)
                       (make-board-member-command))))

(defun make-status-command ()
  "Create the status command."
  (clingon:make-command
   :name "status"
   :description "Show the stored agent identity"
   :handler (lambda (cmd)
              (declare (ignore cmd))
               (with-cli-db
                 (let ((config (cli-site-config "default")))
                   (if config
                       (let ((agent (when (getf config :agent-id)
                                      (get-agent-by-id (getf config :agent-id))))
                             (board (when (getf config :board-id)
                                      (get-board-by-id (getf config :board-id)))))
                         (format t "Agent: ~a~@[ (~a)~]~%"
                                  (getf config :agent-id) (getf agent :name))
                         (format t "Board: ~a~@[ (~a)~]~%"
                                  (getf config :board-id) (getf board :name))
                         (format t "Bearer: ~a~%" (mask-key (getf config :bearer))))
                       (format t "No agent identity configured. Run 'focus agent init' or 'focus agent use'.~%")))))
   :options nil))

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
                       (make-show-command)
                       (make-create-command)
                       (make-update-command)
                       (make-delete-command)
                       (make-comment-command)
                       (make-label-command)
                       (make-agent-command)
                       (make-board-command)
                       (make-user-command)
                       (make-status-command))))
