(in-package :focus)

;;; Group model

(defun create-group (name)
  "Create a new group. Returns the group ID."
  (db-query
   "INSERT INTO groups (name) VALUES ($1) RETURNING id"
   name :single))

(defun get-group-by-id (id)
  "Get group by ID. Returns plist or nil."
  (let ((result (db-query
                 "SELECT id, name, created_at FROM groups WHERE id = $1"
                 id :alists)))
    (when result (alist-to-plist (car result)))))

(defun list-groups ()
  "List all groups ordered by name."
  (pg-query-params
   "SELECT id, name, created_at FROM groups ORDER BY name"
   nil))

(defun update-group (id &key name)
  "Update group name."
  (when name
    (db-query
     "UPDATE groups SET name = $1 WHERE id = $2"
     name id)))

(defun delete-group (id)
  "Delete a group and its members."
  (db-query "DELETE FROM groups WHERE id = $1" id))

;;; Group members

(defun add-group-member (group-id user-id)
  "Add a user to a group."
  (db-query
   "INSERT INTO group_members (group_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
   group-id user-id))

(defun remove-group-member (group-id user-id)
  "Remove a user from a group."
  (db-query
   "DELETE FROM group_members WHERE group_id = $1 AND user_id = $2"
   group-id user-id))

(defun list-group-members (group-id)
  "List all members of a group."
  (pg-query-params
   "SELECT u.id, u.username, u.email, u.picture, u.created_at
    FROM users u
    JOIN group_members gm ON u.id = gm.user_id
    WHERE gm.group_id = $1
    ORDER BY u.username"
   (list group-id)))

(defun list-user-groups (user-id)
  "List all groups a user belongs to."
  (pg-query-params
   "SELECT g.id, g.name, g.created_at
    FROM groups g
    JOIN group_members gm ON g.id = gm.group_id
    WHERE gm.user_id = $1
    ORDER BY g.name"
   (list user-id)))

(defun is-group-member (group-id user-id)
  "Check if a user is a member of a group."
  (let ((result (db-query
                 "SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2"
                 group-id user-id :single)))
    (not (null result))))
