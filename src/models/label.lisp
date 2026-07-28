(in-package :focus)

;;; Label model

(defun create-label (name &key color)
  "Create a new label. Returns the label ID."
  (db-query
   "INSERT INTO labels (name, color) VALUES ($1, $2) RETURNING id"
   name (or color "#3498db")
   :single))

(defun get-label-by-id (id)
  "Get label by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, name, color FROM labels WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-labels ()
  "List all labels. Returns list of plists."
  (pg-query-params
   "SELECT id, name, color FROM labels ORDER BY name"
   nil))

(defun update-label (id &key name color)
  "Update label fields. Returns the updated label."
  (when (or name color)
    (db-execute
     "UPDATE labels SET name = COALESCE($1, name), color = COALESCE($2, color) WHERE id = $3"
     name color id))
  (get-label-by-id id))

(defun delete-label (id)
  "Delete label by ID."
  (db-execute "DELETE FROM labels WHERE id = $1" id))

(defun add-label-to-ticket (ticket-id label-id)
  "Add a label to a ticket."
  (db-execute
   "INSERT INTO ticket_labels (ticket_id, label_id) VALUES ($1, $2) ON CONFLICT DO NOTHING"
   ticket-id label-id))

(defun remove-label-from-ticket (ticket-id label-id)
  "Remove a label from a ticket."
  (db-execute
   "DELETE FROM ticket_labels WHERE ticket_id = $1 AND label_id = $2"
   ticket-id label-id))

(defun get-ticket-labels (ticket-id)
  "Get all labels for a ticket."
  (pg-query-params
   "SELECT l.id, l.name, l.color
    FROM labels l
    JOIN ticket_labels tl ON l.id = tl.label_id
    WHERE tl.ticket_id = $1
    ORDER BY l.name"
   (list ticket-id)))
