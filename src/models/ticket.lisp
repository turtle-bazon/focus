(in-package :focus)

;;; Ticket model

(defun create-ticket (title &key description status priority assignee-id)
  "Create a new ticket. Returns the ticket ID."
  (let ((status (or status "open")))
    (db-query
     "INSERT INTO tickets (title, description, status, priority, assignee_id, position)
      VALUES ($1, $2, $3::varchar, $4, NULLIF($5, 0),
              COALESCE((SELECT MAX(position) + 1 FROM tickets WHERE status = $3::varchar), 0))
      RETURNING id"
     title
     description
     status
     (or priority "medium")
     (or assignee-id 0)
     :single)))

(defun get-ticket-by-id (id)
  "Get ticket by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, title, description, status, priority, assignee_id, position, created_at, updated_at
                   FROM tickets WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-tickets (&key status priority assignee-id (page 1) (limit 20))
  "List tickets with optional filters. Returns list of plists."
  (let ((page (or page 1))
        (limit (or limit 20))
        (conditions '())
        (params '()))
    (when status
      (push "(status = $1)" conditions)
      (push status params))
    (when priority
      (push (format nil "(priority = $~d)" (+ 1 (length params))) conditions)
      (push priority params))
    (when assignee-id
      (push (format nil "(assignee_id = $~d)" (+ 1 (length params))) conditions)
      (push assignee-id params))
    (let ((where (if conditions
                     (format nil "WHERE ~{~a~^ AND ~}" (reverse conditions))
                     ""))
          (all-params (append (reverse params)
                             (list limit (* (- page 1) limit)))))
      (pg-query-params
       (format nil "SELECT id, title, description, status, priority, assignee_id, position, created_at, updated_at
                    FROM tickets ~a
                    ORDER BY CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 ELSE 1 END,
                             position ASC, created_at DESC
                    LIMIT $~d OFFSET $~d"
               where
               (+ 1 (length params))
               (+ 2 (length params)))
       all-params))))

(defun update-ticket (id &key title description status priority assignee-id)
  "Update ticket fields. Returns the updated ticket."
  (let ((sets '())
        (params '())
        (i 0))
    (when title
      (incf i)
      (push (format nil "title = $~d" i) sets)
      (push title params))
    (when description
      (incf i)
      (push (format nil "description = $~d" i) sets)
      (push description params))
    (when status
      (incf i)
      (push (format nil "status = $~d" i) sets)
      (push status params))
    (when priority
      (incf i)
      (push (format nil "priority = $~d" i) sets)
      (push priority params))
    (when assignee-id
      (incf i)
      (push (format nil "assignee_id = $~d" i) sets)
      (push assignee-id params))
    (when sets
      (incf i)
      (push id params)
      (pg-query-params
       (format nil "UPDATE tickets SET ~{~a~^, ~}, updated_at = NOW() WHERE id = $~d"
               (reverse sets) i)
       (reverse params))))
  (get-ticket-by-id id))

(defun reposition-ticket (id new-status new-priority new-position)
  "Move a ticket to a new status/priority/position and reindex the group."
  (db-execute
   "UPDATE tickets SET status = $1, priority = $2, updated_at = NOW() WHERE id = $3"
   new-status new-priority id)
  (let ((others (mapcar (lambda (plist) (getf plist :id))
                        (pg-query-params
                         "SELECT id FROM tickets WHERE status = $1 AND priority = $2 AND id != $3
                          ORDER BY position ASC, created_at DESC"
                         (list new-status new-priority id))))
        (pos (max 0 (min new-position 10000))))
    (let ((ordered (append (subseq others 0 (min pos (length others)))
                           (list id)
                           (subseq others (min pos (length others))))))
      (iter (for idx from 0)
            (for ticket-id in ordered)
            (db-execute
             "UPDATE tickets SET position = $1 WHERE id = $2"
             idx ticket-id))))
  (get-ticket-by-id id))

(defun delete-ticket (id)
  "Delete ticket by ID."
  (db-execute "DELETE FROM tickets WHERE id = $1" id))

(defun search-tickets (search-query)
  "Full-text search tickets by title and description."
  (pg-query-params
   "SELECT id, title, description, status, priority, assignee_id, position, created_at, updated_at
    FROM tickets
    WHERE title ILIKE $1 OR description ILIKE $1
    ORDER BY CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 ELSE 1 END,
             position ASC, created_at DESC"
   (list (format nil "%~a%" search-query))))
