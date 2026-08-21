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
  "Normalize a JSON string key into a hyphenated keyword."
  (intern (substitute #\- #\_ (string-upcase key)) :keyword))

(defun json-> (obj)
  "Convert parsed JSON (jzon structures) into plists: objects become plists,
   arrays become lists, null becomes NIL."
  (cond ((hash-table-p obj)
         (let ((plist nil))
           (iter (for (key value) in-hashtable obj)
             (setf plist (list* (json-key key) (list* (json-> value) plist))))
           plist))
        ((stringp obj) obj)
        ((vectorp obj) (iter (for item in-vector obj) (collecting (json-> item))))
        ((eq obj 'null) nil)
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
    (if parts
        (string/join (nreverse parts) "&")
        nil)))

(defun decode-json-text (text)
  "Decode TEXT as JSON into plists, or return NIL."
  (when (and text (plusp (length text)))
    (ignore-errors (json-> (jzon:parse text :max-string-length nil)))))

(defvar *focus-cli-server* nil
  "Bound to the active site's server URL by WITH-CLI-SITE.")

(defvar *focus-cli-bearer* nil
  "Bound to the active site's bearer token by WITH-CLI-SITE.")

(defvar *focus-cli-server-public* nil
  "Bound to the active site's server public key by WITH-CLI-SITE.")

(defvar *focus-cli-agent-private* nil
  "Bound to the active site's agent private key by WITH-CLI-SITE.")

(defun cli-master-key (&key server-public agent-private)
  "Compute the envelope master key from stored shape credentials."
  (envelope-master-key
   (x25519-shared-secret (x25519-import-private agent-private)
                         (x25519-import-public server-public))))

(defun envelope-request-payload (master method path query body)
  "Build the encrypted request envelope JSON for the inner call."
       (let* ((inner (jzon:stringify
                (hash/make
                  (list (list "method" (string-downcase (symbol-name method)))
                        (list "path" path)
                        (list "query" (or query ""))
                        (list "body" (if body
                                         (jzon:stringify (plist-to-json body))
                                         'null)))
                  :test #'equal)))
         (ts (get-universal-time)))
    (multiple-value-bind (nonce ciphertext tag)
        (envelope-encrypt master +envelope-direction-request+ ts
                          (flexi-streams:string-to-octets inner
                                                          :external-format :utf-8))
      (envelope-encode-json ts nonce ciphertext tag))))

(defun envelope-response-values (master text)
  "Decrypt an envelope response TEXT. Returns (values status body-text).
   Signals api-error on malformed, stale, or tampered envelopes."
  (multiple-value-bind (ts nonce ciphertext tag)
      (ignore-errors (envelope-parse-json text))
    (unless ts
      (error 'api-error :message "Malformed envelope response"))
    (unless (envelope-time-fresh-p ts)
      (error 'api-error :message
             "Envelope response outside the freshness window"))
    (let* ((plaintext (handler-case
                          (envelope-decrypt master +envelope-direction-response+
                                            ts nonce ciphertext tag)
                        (ironclad:bad-authentication-tag ()
                          (error 'api-error :message
                                 "Envelope authentication failed"))))
           (inner (jzon:parse
                   (flexi-streams:octets-to-string plaintext
                                                   :external-format :utf-8)
                   :max-string-length nil)))
      (values (or (envelope-json-key inner "status") 500)
              (or (envelope-json-key inner "body") "")))))

(defun condition-body-text (e)
  "Extract the failed response body of a dexador error E as text."
  (let ((body (dexador:response-body e)))
    (typecase body
      (stream (read-all-stream body))
      (string body)
      (vector (flexi-streams:octets-to-string body :external-format :utf-8))
      (t (princ-to-string body)))))

(defun failed-call-message (master e)
  "Best-effort human message for a failed enveloped API call."
  (let ((text (ignore-errors (condition-body-text e))))
    (or (when text
          (ignore-errors
            (multiple-value-bind (status body-text)
                (envelope-response-values master text)
              (declare (ignore status))
              (getf (decode-json-text body-text) :error))))
        (when text
          (ignore-errors (getf (decode-json-text text) :error)))
        (format nil "HTTP ~a" (dexador:response-status e)))))

(defun cli-progress-p ()
  "Progress lines print only when FOCUS_CLI_TRACE=1."
  (string= (or (uiop:getenv "FOCUS_CLI_TRACE") "") "1"))

(defun cli-progress (fmt &rest args)
  "Print a progress line for the current enveloped call."
  (when (cli-progress-p)
    (apply #'format *error-output* fmt args)))

(defun header-number (headers name)
  "Numeric value of response header NAME, or NIL."
  (when (hash-table-p headers)
    (let ((value (gethash name headers)))
      (and value
           (parse-integer (princ-to-string value) :junk-allowed t)))))

(defun read-stream-exact (stream n)
  "Read exactly N octets from STREAM, erroring if it ends early. Never
   relies on short reads meaning EOF: over TLS a short read just means
   the record boundary was reached."
  (let ((out (make-array n :element-type '(unsigned-byte 8)))
        (pos 0))
    (loop while (< pos n)
          do (let ((got (read-sequence out stream :start pos :end n)))
               (when (= got pos)
                 (error 'api-error
                        :message "Connection closed before full response"))
               (setf pos got)))
    out))

(defun read-stream-to-eof (stream)
  "Read STREAM until a zero-length read (true EOF), returning octets."
  (let ((chunks nil)
        (buf (make-array 65536 :element-type '(unsigned-byte 8))))
    (loop for n = (read-sequence buf stream)
          do (push (subseq buf 0 n) chunks)
          until (zerop n)
          finally (return (apply #'concatenate
                                 '(unsigned-byte 8) (nreverse chunks))))))

(defun api-call (method path &key query body (server *focus-cli-server*)
                                   (bearer *focus-cli-bearer*)
                                   (server-public *focus-cli-server-public*)
                                   (agent-private *focus-cli-agent-private*))
  "Call the API through the encrypted agent envelope. Returns decoded plist(s)
   or signals api-error. Credentials fall back to the site bound by
   WITH-CLI-SITE."
  (unless server
    (error 'api-error :message
           "No server. Run: focus-cli add-site --name NAME --url URL --bearer BEARER --server-public KEY --agent-private KEY"))
  (unless (and bearer server-public agent-private)
    (error 'api-error :message
           "Incomplete credentials. Run: focus-cli add-site --name NAME --url URL --bearer BEARER --server-public KEY --agent-private KEY"))
  (let* ((master (cli-master-key :server-public server-public
                                 :agent-private agent-private))
         (payload (envelope-request-payload master method path query body))
         (url (format nil "~a/api/agent" server))
         (started (get-internal-real-time)))
    ;; Show something before the request: DNS/connect can take seconds and
    ;; a silent wait is indistinguishable from a hang.
    (cli-progress "~&[focus-cli] ~(~a~) ~a ... "
                  (string-downcase (symbol-name method)) path)
    (handler-case
        (multiple-value-bind (body status)
            (dexador:request url :method :post :bearer-auth bearer
                             :content payload
                             :headers '(("content-type" . "application/json"))
                             :force-binary t)
          (declare (ignore status))
          ;; Let dexador frame and assemble the body; reading pooled TLS
          ;; streams ourselves deadlocks against proxies that keep the
          ;; connection open after the response.
          (let* ((text (typecase body
                         (string body)
                         (vector (flexi-streams:octets-to-string
                                  body :external-format :utf-8))
                         (stream (read-stream-to-eof body))
                         (t (princ-to-string body)))))
            (multiple-value-bind (inner-status body-text)
                (envelope-response-values master text)
              (unless (<= 200 inner-status 299)
                (let ((decoded (decode-json-text body-text)))
                  (error 'api-error :message
                         (or (getf decoded :error)
                             (format nil "HTTP ~a" inner-status)))))
              (let ((result (decode-json-text body-text)))
                (cli-progress "ok (~,2fs)~%"
                              (/ (- (get-internal-real-time) started)
                                 internal-time-units-per-second))
                result))))
      (api-error (e)
        (cli-progress "failed~%")
        (error e))
      (dexador.error:http-request-failed (e)
        (cli-progress "failed~%")
        (error 'api-error :message (failed-call-message master e)))
      (error (e)
        (cli-progress "failed~%")
        (error 'api-error :message (princ-to-string e))))))

(defun verify-agent-credentials (server bearer server-public agent-private)
  "Make a live enveloped request to SERVER to confirm these credentials
   actually authenticate before storing them. Returns (VALUES OK ERROR)."
  (handler-case
      (progn
        (let ((*focus-cli-server* server)
              (*focus-cli-bearer* bearer)
              (*focus-cli-server-public* server-public)
              (*focus-cli-agent-private* agent-private))
          (api-call :get "/api/boards"))
        (values t nil))
    (api-error (e) (values nil (api-error-message e)))))

(defmacro with-api-errors (&body body)
  "Run BODY, printing any api-error and continuing."
  `(handler-case (progn ,@body)
     (api-error (e)
       (format t "Error: ~a~%" (api-error-message e)))))

(defmacro with-cli-site ((site) &body body)
  "Run BODY with the active site's connection credentials bound. SITE is a
   form evaluating to a site name."
  `(let* ((site ,site)
          (config (cli-site-config site)))
     (unless config
       (error 'api-error :message
              (format nil "Site ~a not configured. Run: focus-cli add-site --name ~a --url URL --bearer BEARER --server-public KEY --agent-private KEY"
                      site site)))
     (let ((*focus-cli-server* (getf config :server-url))
           (*focus-cli-bearer* (getf config :bearer))
           (*focus-cli-server-public* (getf config :server-public))
           (*focus-cli-agent-private* (getf config :agent-private)))
       ,@body)))

(defun make-site-option ()
  "A required --site option shared by the site-scoped API commands."
  (clingon:make-option :string
                       :long-name "site"
                       :description "Site name (required)"
                       :key :site
                       :required t
                       :env-vars '("FOCUS_SITE")))

(defun make-board-option ()
  "A required --board SITE/BOARD option for the remote list and create commands."
  (clingon:make-option :string
                       :long-name "board"
                       :description "Board as SITE/BOARD, e.g. work/helpdesk"
                       :key :board
                       :required t
                       :env-vars '("FOCUS_BOARD")))

(defun cli-require-board-spec (cmd)
  "Parse the --board SPEC as SITE/BOARD; signals api-error unless both parts
  exist. Returns (values BOARD SITE)."
  (let ((spec (string/trim (or (clingon:getopt cmd :board) "") '(#\Space #\Tab))))
    (unless (position #\/ spec)
      (error 'api-error :message
             "Specify the board as SITE/BOARD, e.g. --board work/helpdesk"))
    (split-board-spec spec)))

(defun remote-list-boards ()
  "Fetch the boards visible to the agent as plists."
  (getf (api-call :get "/api/boards") :boards))

(defun board-id-by-name (boards name)
  "Find the board id in BOARDS whose name matches NAME (case-insensitive)."
  (getf (find name boards
              :key (lambda (board) (getf board :name))
              :test #'string-equal)
        :id))

(defun resolve-board-specs (boards specs)
  "Resolve each SPEC (numeric id or name) in SPECS against BOARDS plists.
  Returns an alist of (board-name . board-id), skipping unknown boards."
  (iter (for spec in specs)
    (let* ((text (string/trim spec " "))
           (id (ignore-errors (parse-integer text)))
           (board (if id
                      (find id boards :key (lambda (b) (getf b :id)) :test #'eql)
                      (find text boards
                            :key (lambda (b) (getf b :name))
                            :test #'string-equal))))
      (when board
        (collecting (cons (getf board :name) (getf board :id)))))))

(defun prompt-local-name (remote)
  "Ask for a local alias for the remote board REMOTE; empty answer keeps REMOTE."
  (format t "Local name for '~a' [~a]: " remote remote)
  (finish-output)
  (let ((line (read-line *standard-input* nil nil)))
    (if (and line (plusp (length (string/trim line '(#\Space #\Tab)))))
        (string/trim line '(#\Space #\Tab))
        remote)))

(defun cli-resolve-board-id (site ref)
  "Resolve REF to a board id in SITE: a numeric id, a stored local alias
   (resolved to its remote name via the API), or a board's remote name.
   Returns NIL when nothing resolves."
  (if-let (num (ignore-errors (parse-integer ref)))
    num
    (board-id-by-name (remote-list-boards)
                      (or (cli-local-board-remote site ref) ref))))

(defun remote-labels (ticket-id)
  "Fetch labels for TICKET-ID via the API."
  (getf (api-call :get (format nil "/api/tickets/~a/labels" ticket-id)) :labels))

(defun remote-show-ticket (ticket json?)
  "Print TICKET with its labels and comments."
  (let* ((labels (remote-labels (getf ticket :id)))
         (result (api-call :get (format nil "/api/tickets/~a/comments" (getf ticket :id))))
         (comments (getf result :comments)))
    (print-ticket-with ticket labels comments json?)))

(defun split-words (text &optional (separators '(#\Space #\Tab #\,)))
  "Split TEXT into trimmed non-empty words on SEPARATORS."
  (let ((delimited (concatenate 'string text (string (car separators)))))
    (iter (with start = 0)
          (for i from 0 below (length delimited))
          (when (member (char delimited i) separators)
            (let ((word (string-trim separators (subseq delimited start i))))
              (when (plusp (length word))
                (collecting word)))
            (setf start (1+ i))))))

(defun pick-boards (boards)
  "Prompt the user to choose one or more boards from BOARDS by number or name
  (space/comma separated; empty answer selects all). Returns an alist of
  (board-name . board-id)."
  (iter (for board in boards)
    (for n from 1)
    (format t "~a. ~a (~a)~%" n (getf board :name) (getf board :type)))
  (format t "Choose boards (numbers or names, space/comma separated; empty = all): ")
  (finish-output)
  (let ((line (read-line *standard-input* nil nil)))
    (if (and line (plusp (length (string/trim line '(#\Space #\Tab)))))
        (let ((texts (split-words line)))
          (iter (for text in texts)
            (let* ((clean (string/trim text '(#\Space #\Tab)))
                   (n (parse-integer clean :junk-allowed t))
                   (board (cond ((and n (<= 1 n (length boards)))
                                 (nth (1- n) boards))
                                ((plusp (length clean))
                                 (find clean boards
                                       :key (lambda (b) (getf b :name))
                                       :test #'string-equal)))))
              (when board
                (collecting (cons (getf board :name) (getf board :id)))))))
        (iter (for board in boards)
          (collecting (cons (getf board :name) (getf board :id)))))))

(defun make-remote-add-site-command ()
  "Create the add-site command."
  (clingon:make-command
   :name "add-site"
   :description "Add a site (server URL + agent shape credentials) to ~/.focus-cli"
   :handler (lambda (cmd)
              (with-api-errors
                (let ((name (clingon:getopt cmd :name))
                      (url (clingon:getopt cmd :url))
                      (bearer (clingon:getopt cmd :bearer))
                      (server-public (clingon:getopt cmd :server-public))
                      (agent-private (clingon:getopt cmd :agent-private)))
                  (if (and name url bearer server-public agent-private)
                      (multiple-value-bind (ok err)
                          (verify-agent-credentials url bearer server-public agent-private)
                        (if ok
                            (cli-add-site name url bearer server-public agent-private)
                            (error 'api-error :message
                                   (format nil "credentials rejected by ~a (~a). ~
Check --bearer, --server-public and --agent-private — swapped, stale, or revoked?"
                                           url err))))
                      (format t "Usage: focus-cli add-site --name NAME --url URL --bearer BEARER --server-public KEY --agent-private KEY~%")))))
   :options (list (clingon:make-option :string
                                        :long-name "name"
                                        :description "Site name"
                                        :key :name
                                        :required t)
                  (clingon:make-option :string
                                        :long-name "url"
                                        :description "Server base URL, e.g. http://host:8080"
                                        :key :url
                                        :required t)
                  (clingon:make-option :string
                                        :long-name "bearer"
                                        :description "Shape bearer token (shown once)"
                                        :key :bearer
                                        :required t)
                  (clingon:make-option :string
                                        :long-name "server-public"
                                        :description "Server X25519 public key (base64)"
                                        :key :server-public
                                        :required t)
                  (clingon:make-option :string
                                        :long-name "agent-private"
                                        :description "Agent X25519 private key (base64)"
                                        :key :agent-private
                                        :required t))))

(defun remote-add-board-by-specs (site boards specs local-name)
  "Add boards matching SPECS to SITE; returns T when something matched."
  (let ((chosen (resolve-board-specs boards specs)))
    (if chosen
        (progn
          (cli-set-site-board site (or local-name (caar chosen)) (caar chosen))
          (format t "Added ~a -> ~a on site ~a.~%" (or local-name (caar chosen))
                  (caar chosen) site)
          t)
        (progn
          (format t "No remote boards matched: ~{~a~^, ~}~%" specs)
          (format t "See available boards: focus-cli list-boards --site ~a~%" site)
          nil))))

(defun remote-add-board-interactively (site boards)
  "Prompt for several boards and local aliases, then record them on SITE."
  (let ((chosen (pick-boards boards)))
    (when chosen
      (iter (for (remote . id) in chosen)
        (declare (ignore id))
        (let ((local (prompt-local-name remote)))
          (cli-set-site-board site local remote)))
      (format t "Added ~a board~:p to site ~a.~%" (length chosen) site))))

(defun remote-add-board-handler (cmd)
  "Handler for the focus-cli add-board command."
  (with-api-errors
    (let ((site (clingon:getopt cmd :site)))
      (with-cli-site (site)
        (let ((boards (remote-list-boards))
              (specs (clingon:getopt cmd :board)))
          (if specs
              (remote-add-board-by-specs site boards specs (clingon:getopt cmd :name))
              (remote-add-board-interactively site boards)))))))

(defun make-remote-add-board-command ()
  "Create the add-board command."
  (clingon:make-command
   :name "add-board"
   :description "Add boards to a site (interactively, or by --board/--name)"
   :handler #'remote-add-board-handler
   :options (list (make-site-option)
                  (clingon:make-option :list
                                        :long-name "board"
                                        :description "Remote board name to add (repeatable)"
                                        :key :board
                                        :parameter "NAME")
                  (clingon:make-option :string
                                        :long-name "name"
                                        :description "Local alias (defaults to the board name)"
                                        :key :name))))

(defun make-remote-list-sites-command ()
  "Create the list-sites command."
  (clingon:make-command
   :name "list-sites"
   :description "List all configured sites and their board aliases"
   :handler (lambda (cmd)
              (declare (ignore cmd))
              (let ((sites (getf (read-cli-config) :sites)))
                (if sites
                    (iter (for (name . site) in sites)
                      (format t "~a  server=~a  bearer=~a~%"
                              name
                              (or (getf site :server-url) "-")
                              (mask-key (getf site :bearer)))
                      (iter (for (local . remote) in (getf site :boards))
                        (format t "    ~a -> ~a~%" local remote)))
                    (format t "No sites configured. Run: focus-cli add-site --name NAME --url URL --bearer BEARER --server-public KEY --agent-private KEY~%"))))
   :options nil))

(defun make-remote-list-boards-command ()
  "Create the list-boards command."
  (clingon:make-command
   :name "list-boards"
   :description "List a site's boards: configured aliases and server boards"
   :handler (lambda (cmd)
              (with-api-errors
                (let ((site (clingon:getopt cmd :site))
                      (aliases (cli-site-boards (clingon:getopt cmd :site))))
                  (format t "Configured on ~a:~%" site)
                  (if aliases
                      (iter (for (local . remote) in aliases)
                        (format t "  ~a -> ~a~%" local remote))
                      (format t "  (none)~%"))
                  (with-cli-site (site)
                    (format t "Available on the server:~%")
                    (iter (for board in (getf (api-call :get "/api/boards") :boards))
                      (format t "  ~a | ~a | ~a~%"
                              (getf board :id)
                              (getf board :name)
                              (getf board :type)))))))
   :options (list (make-site-option))))

(defun remote-list-handler (cmd)
  "Handler for the focus-cli list command."
  (with-api-errors
    (multiple-value-bind (board site) (cli-require-board-spec cmd)
      (with-cli-site (site)
        (let* ((status (clingon:getopt cmd :status))
               (priority (clingon:getopt cmd :priority))
               (assignee (clingon:getopt cmd :assignee))
               (limit (clingon:getopt cmd :limit))
               (page (clingon:getopt cmd :page))
               (search (clingon:getopt cmd :search))
               (json? (clingon:getopt cmd :json))
               (board-id (cli-resolve-board-id site board)))
          (cond (search
                 (print-ticket-list
                  (getf (api-call :get "/api/tickets/search"
                                  :query (build-query `(:q ,search)))
                        :tickets)
                  json?))
                (board-id
                 (print-ticket-list
                  (getf (api-call :get "/api/tickets"
                                  :query (build-query `(:status ,status
                                                         :priority ,priority
                                                         :assignee-id ,assignee
                                                         :board-id ,board-id
                                                         :limit ,limit
                                                         :page ,page)))
                        :tickets)
                  json?))
                (t (format t "Board ~a not found on site ~a.~%" board site)
                   (format t "See: focus-cli list-boards --site ~a~%" site))))))))

(defun make-remote-list-command ()
  "Create the list command."
  (clingon:make-command
   :name "list"
   :description "List tickets in a board"
   :handler #'remote-list-handler
   :options (list (make-board-option)
                  (opt-string "status" "Filter by status" :status)
                  (opt-string "priority" "Filter by priority" :priority)
                  (opt-int "assignee" "Filter by assignee ID" :assignee)
                  (opt-int "limit" "Max tickets to show" :limit :initial-value 20)
                  (opt-int "page" "Page number" :page :initial-value 1)
                  (opt-string "search" "Full-text search query" :search)
                  (opt-flag "json" "Output as JSON" :json))))

(defun make-remote-lifecycle-command ()
  "Create the lifecycle command."
  (clingon:make-command
   :name "lifecycle"
   :description "Show statuses and allowed transitions for a board"
   :handler (lambda (cmd)
              (with-api-errors
                (multiple-value-bind (board site) (cli-require-board-spec cmd)
                  (with-cli-site (site)
                    (let ((board-id (cli-resolve-board-id site board)))
                      (if board-id
                          (let* ((statuses (getf (api-call :get (format nil "/api/boards/~a/statuses" board-id))
                                                 :statuses))
                                 (transitions (getf (api-call :get (format nil "/api/boards/~a/transitions" board-id))
                                                    :transitions)))
                            (format t "Statuses:~%")
                            (iter (for s in statuses)
                              (format t "  ~a~@[ (~a)~]~%"
                                      (getf s :code) (getf s :name)))
                            (format t "~%Transitions:~%")
                            (if transitions
                                (iter (for tr in transitions)
                                  (format t "  ~a -> ~a~%"
                                          (getf tr :from-code) (getf tr :to-code)))
                                (format t "  (none)~%")))
                          (format t "Board ~a not found on site ~a.~%" board site)))))))
   :options (list (make-board-option))))

(defun make-remote-show-command ()
  "Create the show command."
  (clingon:make-command
   :name "show"
   :description "Show ticket details, labels, and comments"
   :handler (lambda (cmd)
              (with-api-errors
                (with-cli-site ((clingon:getopt cmd :site))
                  (let* ((id (cli-int-arg cmd 0))
                         (ticket (when id (api-call :get (format nil "/api/tickets/~a" id)))))
                    (if ticket
                        (remote-show-ticket ticket (clingon:getopt cmd :json))
                        (format t "Ticket not found~%"))))))
   :options (list (make-site-option)
                  (clingon:make-option :flag :long-name "json"
                                       :description "Output as JSON" :key :json))))

(defun make-remote-create-command ()
  "Create the create command."
  (clingon:make-command
   :name "create"
   :description "Create a new ticket in a board"
   :handler (lambda (cmd)
              (with-api-errors
                (multiple-value-bind (board site) (cli-require-board-spec cmd)
                  (with-cli-site (site)
                    (let ((title (clingon:getopt cmd :title))
                          (board-id (cli-resolve-board-id site board)))
                      (if board-id
                          (let ((result (api-call :post "/api/tickets"
                                                  :body `(:title ,title
                                                           :board-id ,board-id
                                                           :description ,(clingon:getopt cmd :description)
                                                           :status ,(clingon:getopt cmd :status)
                                                           :priority ,(clingon:getopt cmd :priority)
                                                           :assignee-id ,(clingon:getopt cmd :assignee)
                                                           :color ,(clingon:getopt cmd :color)))))
                            (format t "Created ticket ~a~%" (getf result :id)))
                          (format t "Board ~a not found on site ~a.~%" board site)))))))
   :options (list (make-board-option)
                  (clingon:make-option :string :long-name "title"
                                       :description "Ticket title" :key :title :required t)
                  (clingon:make-option :string :long-name "description"
                                       :description "Ticket description" :key :description)
                  (clingon:make-option :string :long-name "priority"
                                       :description "Ticket priority" :key :priority
                                       :initial-value "medium")
                  (clingon:make-option :string :long-name "status"
                                       :description "Ticket status" :key :status
                                       :initial-value "open")
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
                (with-cli-site ((clingon:getopt cmd :site))
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
                        (format t "Ticket not found~%"))))))
   :options (list (make-site-option)
                  (clingon:make-option :string :long-name "title"
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
                (with-cli-site ((clingon:getopt cmd :site))
                  (let ((id (cli-int-arg cmd 0)))
                    (if id
                        (progn
                          (api-call :delete (format nil "/api/tickets/~a" id))
                          (format t "Deleted ticket ~a~%" id))
                        (format t "Missing ticket ID~%")))))) 
   :options (list (make-site-option))))

(defun make-remote-comment-add-command ()
  "Create the comment add command."
  (clingon:make-command
   :name "add"
   :description "Add a comment to a ticket (as the stored agent)"
   :handler (lambda (cmd)
              (with-api-errors
                (with-cli-site ((clingon:getopt cmd :site))
                  (let* ((ticket (cli-int-arg cmd 0))
                         (body (clingon:getopt cmd :body))
                         (result (when (and ticket body)
                                   (api-call :post (format nil "/api/tickets/~a/comments" ticket)
                                             :body `(:body ,body)))))
                    (if result
                        (format t "Added comment ~a to ticket ~a~%" (getf result :id) ticket)
                        (format t "Usage: focus-cli comment add TICKET --body TEXT~%"))))))
   :options (list (make-site-option)
                  (clingon:make-option :string :long-name "body"
                                       :description "Comment text" :key :body :required t))))

(defun make-remote-comment-list-command ()
  "Create the comment list command."
  (clingon:make-command
   :name "list"
   :description "List comments on a ticket"
   :handler (lambda (cmd)
              (with-api-errors
                (with-cli-site ((clingon:getopt cmd :site))
                  (let ((ticket (cli-int-arg cmd 0)))
                    (if ticket
                        (iter (for comment in (getf (api-call :get
                                                              (format nil "/api/tickets/~a/comments" ticket))
                                                    :comments))
                          (format t "~a | ~a~%" (getf comment :id) (getf comment :body)))
                        (format t "Missing ticket ID~%"))))))
   :options (list (make-site-option))))

(defun make-remote-comment-delete-command ()
  "Create the comment delete command."
  (clingon:make-command
   :name "delete"
   :description "Delete a comment from a ticket"
   :handler (lambda (cmd)
              (with-api-errors
                (with-cli-site ((clingon:getopt cmd :site))
                  (let ((ticket (cli-int-arg cmd 0))
                        (comment (cli-int-arg cmd 1)))
                    (if (and ticket comment)
                        (progn
                          (api-call :delete (format nil "/api/tickets/~a/comments/~a" ticket comment))
                          (format t "Deleted comment ~a from ticket ~a~%" comment ticket))
                        (format t "Usage: focus-cli comment delete TICKET COMMENT~%"))))))
   :options (list (make-site-option))))

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
              (with-api-errors
                (with-cli-site ((clingon:getopt cmd :site))
                  (iter (for label in (getf (api-call :get "/api/labels") :labels))
                    (format t "~a | ~a | ~a~%"
                            (getf label :id)
                            (getf label :name)
                            (getf label :color))))))
   :options (list (make-site-option))))

(defun make-remote-label-tag-command (name description post)
  "Create a shared label add/remove command by NAME."
  (clingon:make-command
   :name name
   :description description
   :handler (lambda (cmd)
              (with-api-errors
                (with-cli-site ((clingon:getopt cmd :site))
                  (let ((ticket (cli-int-arg cmd 0))
                        (label (cli-int-arg cmd 1)))
                    (if (and ticket label)
                        (progn
                          (api-call (if post :post :delete)
                                    (format nil "/api/tickets/~a/labels/~a" ticket label))
                          (format t "~a label ~a ~a ticket ~a~%"
                                  (if post "Added" "Removed") label (if post "to" "from") ticket))
                        (format t "Usage: focus-cli label ~a TICKET LABEL~%" name))))))
   :options (list (make-site-option))))

(defun make-remote-label-command ()
  "Create the label command group."
  (clingon:make-command
   :name "label"
   :description "Manage labels"
   :sub-commands (list (make-remote-label-list-command)
                       (make-remote-label-tag-command "add" "Add a label to a ticket" t)
                       (make-remote-label-tag-command "remove" "Remove a label from a ticket" nil))))

(defun make-remote-root-command ()
  "Create the focus-cli root command."
  (clingon:make-command
   :name "focus-cli"
   :description "Remote command-line client for the Focus ticket server"
   :handler (lambda (cmd)
              (declare (ignore cmd))
              (format t "No subcommand given. See 'focus-cli --help'.~%"))
   :sub-commands (list (make-remote-add-site-command)
                       (make-remote-add-board-command)
                       (make-remote-list-sites-command)
                       (make-remote-list-boards-command)
                       (make-remote-list-command)
                       (make-remote-lifecycle-command)
                       (make-remote-show-command)
                       (make-remote-create-command)
                       (make-remote-update-command)
                       (make-remote-delete-command)
                       (make-remote-comment-command)
                       (make-remote-label-command))))

(defun remote-main ()
  "Entry point for the focus-cli binary."
  ;; Re-anchor logging to this process (see reload-foreign-libraries).
  ;; The CLI talks synchronous HTTP via dexador/usocket: it needs TLS but
  ;; never the libuv event loop, so skip libuv instead of warning about it.
  (bl:configure-log-level :info)
  (bl:configure-log-path nil)
  (reload-foreign-libraries :skip-libraries '("LIBUV")
                            :required-symbols '("SSL_new"))
  (clingon:run (make-remote-root-command)))