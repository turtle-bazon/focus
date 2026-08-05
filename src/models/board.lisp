(in-package :focus)

;;; Board model

(defun get-board-by-id (id)
  "Get a board by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, name, type, is_default, owner_id, created_at
                   FROM boards WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun user-role (user-id)
  "Role string for a user, or nil."
  (let ((user (get-user-by-id user-id)))
    (when user (getf user :role))))

(defun manager-p (user-id)
  "True if the user is an admin or group manager."
  (let ((role (user-role user-id)))
    (member role '("admin" "group_manager") :test #'string=)))

(defun list-visible-boards (user-id)
  "Boards visible to a user: default board, boards where the user (or a group
   they belong to) is a member, boards they own. Admins/managers see all.
   With no user (nil), only the default board is visible."
  (when (null user-id)
    (return-from list-visible-boards
      (pg-query-params
       "SELECT id, name, type, is_default, owner_id, created_at
        FROM boards WHERE is_default ORDER BY name"
       '())))
  (if (manager-p user-id)
      (pg-query-params
       "SELECT id, name, type, is_default, owner_id, created_at
        FROM boards ORDER BY is_default DESC, name"
       '())
      (pg-query-params
       "SELECT DISTINCT b.id, b.name, b.type, b.is_default, b.owner_id, b.created_at
        FROM boards b
        LEFT JOIN board_members bm ON bm.board_id = b.id
        LEFT JOIN group_members gm ON gm.group_id = bm.member_id AND bm.member_type = 'group'
        WHERE b.is_default
           OR b.owner_id = $1
           OR (bm.member_type = 'user' AND bm.member_id = $1)
           OR gm.user_id = $1
        ORDER BY b.is_default DESC, b.name"
       (list user-id))))

(defun seed-board-lifecycle (board-id)
  "Seed a board with the default status column set and allowed transitions."
  (let ((statuses '(("backlog" "Backlog" "#6b7280" 0)
                    ("open" "Open" "#3b82f6" 1)
                    ("in_progress" "In Progress" "#f59e0b" 2)
                    ("review" "Review" "#8b5cf6" 3)
                    ("done" "Done" "#10b981" 4)))
        (transitions '(("backlog" "open")
                       ("open" "in_progress")
                       ("open" "done")
                       ("in_progress" "review")
                       ("in_progress" "open")
                       ("review" "done")
                       ("review" "in_progress")
                       ("done" "open"))))
    (iter (for (code name color position) in statuses)
      (db-query
       "INSERT INTO board_statuses (board_id, code, name, color, position)
        VALUES ($1, $2, $3, $4, $5)"
       board-id code name color position))
    (iter (for (from-code to-code) in transitions)
      (db-query
       "INSERT INTO board_transitions (board_id, from_code, to_code)
        VALUES ($1, $2, $3)"
       board-id from-code to-code))))

(defun create-board (name type owner-id)
  "Create a board with a default lifecycle. TYPE is 'common' or 'personal'.
   Returns the board ID."
  (let ((board-id (db-query
                   "INSERT INTO boards (name, type, owner_id) VALUES ($1, $2, $3) RETURNING id"
                   name type owner-id :single)))
    (seed-board-lifecycle board-id)
    board-id))

(defun update-board (id &key name)
  "Update a board's fields."
  (let ((sets '())
        (params '())
        (i 0))
    (when name
      (incf i)
      (push (format nil "name = $~d" i) sets)
      (push name params))
    (when sets
      (incf i)
      (push id params)
      (pg-query-params
       (format nil "UPDATE boards SET ~{~a~^, ~} WHERE id = $~d"
               (reverse sets) i)
       (reverse params))))
  (get-board-by-id id))

(defun delete-board (id)
  "Delete a board. Cascades to memberships, statuses, and transitions."
  (db-execute "DELETE FROM boards WHERE id = $1" id))

(defun can-manage-board (board-id user-id)
  "True if the user may edit board membership or lifecycle: owner, admin, or group manager."
  (and user-id
       (let ((board (get-board-by-id board-id)))
         (or (not board)
             (= (or (getf board :owner-id) 0) user-id)
             (manager-p user-id)))))

;;; Board membership

(defun list-board-members (board-id)
  "List members of a board."
  (pg-query-params
   "SELECT member_type, member_id FROM board_members WHERE board_id = $1"
   (list board-id)))

(defun ensure-board-member (board-id member-type member-id)
  "Add a member to a board if not already present."
  (db-query
   "INSERT INTO board_members (board_id, member_type, member_id)
    VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"
   board-id member-type member-id))

(defun remove-board-member (board-id member-type member-id)
  "Remove a member from a board."
  (db-query
   "DELETE FROM board_members WHERE board_id = $1 AND member_type = $2 AND member_id = $3"
   board-id member-type member-id))

;;; Board lifecycle (statuses)

(defun list-board-statuses (board-id)
  "List statuses for a board, ordered by position."
  (pg-query-params
   "SELECT id, board_id, code, name, color, position
    FROM board_statuses WHERE board_id = $1
    ORDER BY position ASC, id ASC"
   (list board-id)))

(defun create-board-status (board-id code name &key color position)
  "Create a status in a board. Returns the new status ID."
  (if position
      (db-query
       "INSERT INTO board_statuses (board_id, code, name, color, position)
        VALUES ($1, $2, $3, $4, $5) RETURNING id"
       board-id code name (or color "#6b7280") position :single)
      (db-query
       "INSERT INTO board_statuses (board_id, code, name, color, position)
        VALUES ($1, $2, $3, $4,
                (SELECT COALESCE(MAX(position) + 1, 0)
                 FROM board_statuses WHERE board_id = $1))
        RETURNING id"
       board-id code name (or color "#6b7280") :single)))

(defun update-board-status (board-id status-id &key name color position)
  "Update a status's display fields."
  (let ((sets '())
        (params '())
        (i 0))
    (when name
      (incf i)
      (push (format nil "name = $~d" i) sets)
      (push name params))
    (when color
      (incf i)
      (push (format nil "color = $~d" i) sets)
      (push color params))
    (when position
      (incf i)
      (push (format nil "position = $~d" i) sets)
      (push position params))
    (when sets
      (let* ((p0 i)
             (all-params (append (reverse params)
                                 (list board-id status-id))))
        (pg-query-params
         (format nil "UPDATE board_statuses SET ~{~a~^, ~} WHERE board_id = $~d AND id = $~d"
                 (reverse sets) (1+ p0) (+ 2 p0))
         all-params)))
  t))

(defun delete-board-status (board-id status-id)
  "Delete a status and its transitions."
  (let ((code (db-query "SELECT code FROM board_statuses WHERE id = $1" status-id :single)))
    (when code
      (db-execute "DELETE FROM board_transitions WHERE board_id = $1 AND (from_code = $2 OR to_code = $2)"
                  board-id code))
    (db-execute "DELETE FROM board_statuses WHERE id = $1 AND board_id = $2"
                status-id board-id)))

(defun transition-allowed-p (board-id from-code to-code)
  "True if moving a ticket from FROM-CODE to TO-CODE is allowed in the board."
  (when (equal from-code to-code)
    (return-from transition-allowed-p t))
  (let ((result (db-query
                 "SELECT 1 FROM board_transitions
                  WHERE board_id = $1 AND from_code = $2 AND to_code = $3"
                 board-id from-code to-code :single)))
    (eq result 1)))

;;; Board transitions

(defun list-board-transitions (board-id)
  "List allowed transitions for a board."
  (pg-query-params
   "SELECT id, board_id, from_code, to_code
    FROM board_transitions WHERE board_id = $1"
   (list board-id)))

(defun add-board-transition (board-id from-code to-code)
  "Add an allowed transition."
  (db-query
   "INSERT INTO board_transitions (board_id, from_code, to_code)
    VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"
   board-id from-code to-code))

(defun remove-board-transition (board-id from-code to-code)
  "Remove an allowed transition."
  (db-query
   "DELETE FROM board_transitions
    WHERE board_id = $1 AND from_code = $2 AND to_code = $3"
   board-id from-code to-code))