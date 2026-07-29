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

(defun get-activity-by-id (id)
  "Get activity by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, ticket_id, user_id, action, details, created_at
                   FROM activity WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))
