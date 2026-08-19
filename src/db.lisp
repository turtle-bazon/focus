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

;;; PostgreSQL connection

(defvar *db-connection* nil)
(defvar *db-config* nil)

(defun connect-db (config)
  (setf *db-config* config)
  (setf *db-connection*
        (postmodern:connect-toplevel
         (config->db-name config)
         (config->db-user config)
         (config->db-pass config)
         (config->db-host config)
         :port (config->db-port config)))
  (postmodern:execute "SET timezone TO 'UTC'")
  (bl:info "Connected to PostgreSQL ~a:~a" (config->db-host config) (config->db-name config)))

(defun disconnect-db ()
  (when *db-connection*
    (postmodern:disconnect-toplevel)
    (setf *db-connection* nil)
    (bl:info "Disconnected from PostgreSQL")))

(defun call-with-reconnect (fun)
  "Call FUN, auto-reconnecting on first database connection error."
  (let ((reconnected nil))
    (handler-bind
        ((cl-postgres:database-connection-error
          (lambda (err)
            (unless reconnected
              (setf reconnected t)
              (bl:warn "Connection lost (~a), reconnecting..."
                       (cl-postgres:database-error-message err))
              (invoke-restart :reconnect)))))
      (funcall fun))))

;;; Drop-in wrappers for postmodern:query and postmodern:execute

(defmacro db-query (sql &rest args)
  "Execute SQL query with auto-reconnect."
  `(call-with-reconnect
    (lambda ()
      (postmodern:query ,sql ,@args))))

(defmacro db-execute (sql &rest args)
  "Execute SQL statement with auto-reconnect."
  `(call-with-reconnect
    (lambda ()
      (postmodern:execute ,sql ,@args))))

;;; Parameterized queries

(defun sql-null-or (value)
  "Return :null (SQL NULL) for NIL, else VALUE. Use for optional integer
   parameters — cl-postgres cannot bind NIL to integer columns."
  (or value :null))

(defun alist-to-plist (alist)
  "Convert an alist to a plist. SQL NULL values (postmodern returns the
   keyword :null) are normalized to NIL."
  (when alist
    (iter (for pair in alist)
      (collecting (intern (string-upcase (car pair)) :keyword))
      (collecting (if (eq (cdr pair) :null) nil (cdr pair))))))

(defun hyphenate-plist-keys (plist)
  "Return PLIST with underscores in keyword keys replaced by hyphens, to
   match the app-wide keyword convention (:owner-id, :created-at)."
  (when plist
    (iter (for (key val) on plist by #'cddr)
      (collecting (if (keywordp key)
                      (intern (substitute #\- #\_ (string key)) :keyword)
                      key))
      (collecting val))))

(defun pg-query-params (sql params)
  "Execute a parameterized query on PostgreSQL.
SQL uses $1, $2, etc. PARAMS is a list of values. Returns rows as plists."
  (call-with-reconnect
   (lambda ()
     (let ((conn postmodern:*database*))
       (cl-postgres:prepare-query conn "pg-query-params-stmt" sql)
       (unwind-protect
            (iter (for alist in (cl-postgres:exec-prepared
                                 conn "pg-query-params-stmt" params
                                 'cl-postgres:alist-row-reader))
                  (collecting (alist-to-plist alist)))
         (cl-postgres:unprepare-query conn "pg-query-params-stmt"))))))

;;; Schema version

(defun current-version ()
  (call-with-reconnect
   (lambda ()
     (handler-case
         (postmodern:query
          "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1"
          :single)
       (error () 0)))))

(defun set-version (version)
  (call-with-reconnect
   (lambda ()
     (handler-case
         (postmodern:execute
          "INSERT INTO schema_version (version) VALUES ($1)" version)
       (error ()
         (bl:info "Version ~a already recorded" version))))))

;;; Migration runner

(defun split-sql (sql)
  "Split SQL string by semicolons, handling dollar-quoted strings."
  (bind ((result '())
        (current (make-array 0 :element-type 'character :adjustable t :fill-pointer 0))
        (i 0)
        (len (length sql))
        (in-dollar nil))
    (iter (while (< i len))
      (bind ((ch (char sql i)))
        (cond
          ;; Check for $$ delimiter
          ((and (char= ch #\$)
                (< (1+ i) len)
                (char= (char sql (1+ i)) #\$))
           (if in-dollar
               (progn
                 (vector-push-extend #\$ current)
                 (vector-push-extend #\$ current)
                 (incf i 2)
                 (setf in-dollar nil))
               (progn
                 (vector-push-extend #\$ current)
                 (vector-push-extend #\$ current)
                 (incf i 2)
                 (setf in-dollar t))))
          ;; Split on semicolons only when not inside dollar-quoted block
          ((and (char= ch #\;) (not in-dollar))
            (bind ((trimmed (string-trim " " (copy-seq current))))
             (unless (string= trimmed "")
               (push trimmed result)))
           (setf current (make-array 0 :element-type 'character :adjustable t :fill-pointer 0))
           (incf i))
          ;; Regular character
          (t
           (vector-push-extend ch current)
           (incf i)))))
    ;; Push the last statement
    (bind ((trimmed (string-trim " " (copy-seq current))))
      (unless (string= trimmed "")
        (push trimmed result)))
    (nreverse result)))

(defun migrate-up (&optional (migrations *migrations*))
  (bind ((current (current-version)))
    (iter (for (name &key up down) in migrations)
      (for version = (parse-integer (subseq name 0 4)))
      (when (> version current)
        (bl:info "Migrating up: ~a" name)
        (call-with-reconnect
         (lambda ()
           (iter (for stmt in (split-sql up))
             (bind ((trimmed (string-trim " " stmt)))
               (unless (string= trimmed "")
                 (postmodern:execute trimmed))))))
        (set-version version)
        (bl:info "Applied: ~a" name)))
    (bl:info "Schema at version ~d" (current-version))))

(defun migrate-down (&optional (migrations *migrations*))
  (bind ((current (current-version)))
    (iter (for (name &key up down) in (reverse migrations))
      (for version = (parse-integer (subseq name 0 4)))
      (when (<= version current)
        (bl:info "Migrating down: ~a" name)
        (call-with-reconnect
         (lambda ()
           (iter (for stmt in (split-sql down))
             (bind ((trimmed (string-trim " " stmt)))
               (unless (string= trimmed "")
                 (postmodern:execute trimmed))))
           (postmodern:execute
            "DELETE FROM schema_version WHERE version = $1" version)))
        (bl:info "Rolled back: ~a" name)))
    (bl:info "Schema at version ~d" (current-version))))
