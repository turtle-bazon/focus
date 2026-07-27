(in-package :focus)

;;; Issue model

(defun create-issue (title &key description status priority assignee-id)
  "Create a new issue. Returns the issue ID."
  (db-query
   "INSERT INTO issues (title, description, status, priority, assignee_id)
    VALUES ($1, $2, $3, $4, NULLIF($5, 0)) RETURNING id"
   title
   description
   (or status "open")
   (or priority "medium")
   (or assignee-id 0)
   :single))

(defun get-issue-by-id (id)
  "Get issue by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, title, description, status, priority, assignee_id, created_at, updated_at
                   FROM issues WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-issues (&key status priority assignee-id (page 1) (limit 20))
  "List issues with optional filters. Returns list of plists."
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
       (format nil "SELECT id, title, description, status, priority, assignee_id, created_at, updated_at
                    FROM issues ~a
                    ORDER BY created_at DESC
                    LIMIT $~d OFFSET $~d"
               where
               (+ 1 (length params))
               (+ 2 (length params)))
       all-params))))

(defun update-issue (id &key title description status priority assignee-id)
  "Update issue fields. Returns the updated issue."
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
       (format nil "UPDATE issues SET ~{~a~^, ~}, updated_at = NOW() WHERE id = $~d"
               (reverse sets) i)
       (reverse params))))
  (get-issue-by-id id))

(defun delete-issue (id)
  "Delete issue by ID."
  (db-execute "DELETE FROM issues WHERE id = $1" id))

(defun search-issues (search-query)
  "Full-text search issues by title and description."
  (pg-query-params
   "SELECT id, title, description, status, priority, assignee_id, created_at, updated_at
    FROM issues
    WHERE title ILIKE $1 OR description ILIKE $1
    ORDER BY created_at DESC"
   (list (format nil "%~a%" search-query))))
