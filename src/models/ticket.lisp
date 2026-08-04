(in-package :focus)

;;; Ticket model

(defun get-default-board-id ()
  "ID of the default board everyone sees, or nil."
  (db-query "SELECT id FROM boards WHERE is_default LIMIT 1" :single))

(defun create-ticket (title &key description status priority assignee-id assignee-type color board-id)
  "Create a new ticket. Returns the ticket ID."
  (let ((status (or status "open"))
        (assignee-type (or assignee-type "user"))
        (board-id (or board-id (get-default-board-id))))
    (db-query
     "INSERT INTO tickets (title, description, status, priority, assignee_id, assignee_type, color, board_id, position_num, position_den)
       VALUES ($1, $2, $3::varchar, $4, NULLIF($5, 0), $6, $7, $8,
               COALESCE((SELECT MAX(position_num) + 1 FROM tickets WHERE status = $3::varchar), 0),
               1)
       RETURNING id"
     title
     description
     status
     (or priority "medium")
     (or assignee-id 0)
     assignee-type
     (or color "#6b7280")
     board-id
     :single)))

(defun get-ticket-by-id (id)
  "Get ticket by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, title, description, status, priority, assignee_id, assignee_type, color,
                          board_id, position_num, position_den, created_at, updated_at
                   FROM tickets WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-tickets (&key status priority assignee-id board-id (page 1) (limit 20))
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
    (when board-id
      (push (format nil "(board_id = $~d)" (+ 1 (length params))) conditions)
      (push board-id params))
    (let ((where (if conditions
                     (format nil "WHERE ~{~a~^ AND ~}" (reverse conditions))
                     ""))
          (all-params (append (reverse params)
                             (list limit (* (- page 1) limit)))))
      (pg-query-params
       (format nil "SELECT id, title, description, status, priority, assignee_id, assignee_type, color,
                           board_id, position_num, position_den, created_at, updated_at
                    FROM tickets ~a
                    ORDER BY CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 ELSE 1 END,
                             (position_num::float / position_den) ASC, created_at DESC
                    LIMIT $~d OFFSET $~d"
               where
               (+ 1 (length params))
               (+ 2 (length params)))
       all-params))))

(defun update-ticket (id &key title description status priority assignee-id assignee-type color board-id)
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
    (when assignee-type
      (incf i)
      (push (format nil "assignee_type = $~d" i) sets)
      (push assignee-type params))
    (when color
      (incf i)
      (push (format nil "color = $~d" i) sets)
      (push color params))
    (when board-id
      (incf i)
      (push (format nil "board_id = $~d" i) sets)
      (push board-id params))
    (when sets
      (incf i)
      (push id params)
      (pg-query-params
       (format nil "UPDATE tickets SET ~{~a~^, ~}, updated_at = NOW() WHERE id = $~d"
               (reverse sets) i)
       (reverse params))))
  (get-ticket-by-id id))

(defconstant +compression-threshold+ 1000
  "Compress fractional positions when denominator exceeds this.")

(defun compress-positions (ticket-ids)
  "Reassign contiguous integer positions to a list of ticket IDs."
  (iter (for idx from 0)
        (for ticket-id in ticket-ids)
        (db-execute
         "UPDATE tickets SET position_num = $1, position_den = 1 WHERE id = $2"
         idx ticket-id)))

(defun reposition-ticket (id new-status new-priority new-position)
  "Move a ticket using fractional indexing. Only updates the moved ticket.
   Compresses the group when denominators grow too large."
  (let ((board-id (getf (get-ticket-by-id id) :board-id)))
    ;; Step 1: move ticket to target group
    (db-execute
     "UPDATE tickets SET status = $1, priority = $2, updated_at = NOW() WHERE id = $3"
     new-status new-priority id)
    ;; Step 2: get neighbors in the group (ordered)
    (let ((neighbors (pg-query-params
                      "SELECT id, position_num, position_den
                       FROM tickets WHERE status = $1 AND priority = $2 AND id != $3 AND board_id = $4
                       ORDER BY (position_num::float / position_den) ASC, created_at DESC"
                      (list new-status new-priority id board-id)))
        (pos (max 0 (min new-position 10000))))
    ;; Step 3: find neighbors at target position
    (let ((before (when (and (plusp pos) (>= (length neighbors) pos))
                    (elt neighbors (1- pos))))
          (after (when (< pos (length neighbors))
                   (elt neighbors pos))))
      ;; Step 4: compute mediant position
      ;; Mediant of a/b and c/d is (a+c)/(b+d), always between the two fractions.
      ;; "before first": mediant of sentinel 0/1 and after → after-num/(after-den+1)
      ;; "after last": before-num/before-den + 1 → (before-num+before-den)/before-den
      (let ((new-num (cond
                       ((and before after)
                        (+ (getf before :position_num) (getf after :position_num)))
                       (before
                        (+ (getf before :position_num)
                           (getf before :position_den)))
                       (after
                        (getf after :position_num))
                       (t 0)))
            (new-den (cond
                       ((and before after)
                        (+ (getf before :position_den) (getf after :position_den)))
                       (before
                        (getf before :position_den))
                       (after
                        (1+ (getf after :position_den)))
                       (t 1))))
        ;; Step 5: assign position
        (db-execute
         "UPDATE tickets SET position_num = $1, position_den = $2, updated_at = NOW() WHERE id = $3"
         new-num new-den id)
        ;; Step 6: compress if denominator too large
        (when (> new-den +compression-threshold+)
          (let ((all-ids (mapcar (lambda (plist) (getf plist :id))
                                 (pg-query-params
                                  "SELECT id FROM tickets WHERE status = $1 AND priority = $2 AND board_id = $3
                                   ORDER BY (position_num::float / position_den) ASC, created_at DESC"
                                  (list new-status new-priority board-id)))))
            (compress-positions all-ids)))))))
  (get-ticket-by-id id))

(defun delete-ticket (id)
  "Delete ticket by ID."
  (db-execute "DELETE FROM tickets WHERE id = $1" id))

(defun search-tickets (search-query)
  "Full-text search tickets by title and description."
  (pg-query-params
   "SELECT id, title, description, status, priority, assignee_id, assignee_type, color,
           board_id, position_num, position_den, created_at, updated_at
    FROM tickets
    WHERE title ILIKE $1 OR description ILIKE $1
    ORDER BY CASE priority WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 ELSE 1 END,
             (position_num::float / position_den) ASC, created_at DESC"
   (list (format nil "%~a%" search-query))))
