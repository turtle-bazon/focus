(in-package :focus)

;;; Issue model

(defun create-issue (title &key description status priority assignee-id)
  "Create a new issue. Returns the issue ID."
  (let ((status (or status "open")))
    (db-query
     "INSERT INTO issues (title, description, status, priority, assignee_id, position)
      VALUES ($1, $2, $3::varchar, $4, NULLIF($5, 0),
              COALESCE((SELECT MAX(position) + 1 FROM issues WHERE status = $3::varchar), 0))
      RETURNING id"
     title
     description
     status
     (or priority "medium")
     (or assignee-id 0)
     :single)))

(defun get-issue-by-id (id)
  "Get issue by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, title, description, status, priority, assignee_id, position, created_at, updated_at
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
       (format nil "SELECT id, title, description, status, priority, assignee_id, position, created_at, updated_at
                    FROM issues ~a
                    ORDER BY CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 ELSE 1 END,
                             position ASC, created_at DESC
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

(defun reposition-issue (id new-status new-priority new-position)
  "Move an issue to a new status/priority/position and reindex the group."
  ;; Step 1: move issue to the target group
  (db-execute
   "UPDATE issues SET status = $1, priority = $2, updated_at = NOW() WHERE id = $3"
   new-status new-priority id)
  ;; Step 2: reindex all issues in the group
  ;; Get all issue IDs in order, excluding the moved one
  (let ((others (mapcar (lambda (plist) (getf plist :id))
                        (pg-query-params
                         "SELECT id FROM issues WHERE status = $1 AND priority = $2 AND id != $3
                          ORDER BY position ASC, created_at DESC"
                         (list new-status new-priority id))))
        (pos (max 0 (min new-position 10000))))
    ;; Build the reordered list: insert moved issue at target position
    (let ((ordered (append (subseq others 0 (min pos (length others)))
                           (list id)
                           (subseq others (min pos (length others))))))
      ;; Assign contiguous positions
      (iter (for idx from 0)
            (for issue-id in ordered)
            (db-execute
             "UPDATE issues SET position = $1 WHERE id = $2"
             idx issue-id))))
  (get-issue-by-id id))

(defun delete-issue (id)
  "Delete issue by ID."
  (db-execute "DELETE FROM issues WHERE id = $1" id))

(defun search-issues (search-query)
  "Full-text search issues by title and description."
  (pg-query-params
   "SELECT id, title, description, status, priority, assignee_id, position, created_at, updated_at
    FROM issues
    WHERE title ILIKE $1 OR description ILIKE $1
    ORDER BY CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 ELSE 1 END,
             position ASC, created_at DESC"
   (list (format nil "%~a%" search-query))))
