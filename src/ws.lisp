(in-package :focus)

;;; WebSocket connections

(defvar *ws-connections* (make-hash-table :test 'equal))
(defvar *ws-lock* (bt:make-lock "ws-connections"))

(defun ws-add-connection (id connection)
  "Add a WebSocket connection."
  (bt:with-lock-held (*ws-lock*)
    (setf (gethash id *ws-connections*) connection)))

(defun ws-remove-connection (id)
  "Remove a WebSocket connection."
  (bt:with-lock-held (*ws-lock*)
    (remhash id *ws-connections*)))

(defun ws-broadcast (message)
  "Broadcast a message to all connected clients."
  (bt:with-lock-held (*ws-lock*)
    (maphash (lambda (id conn)
               (declare (ignore id))
               (handler-case
                   (websocket-driver:send conn message)
                 (error ()
                   (ws-remove-connection id))))
             *ws-connections*)))

(defun ws-broadcast-issue-update (issue)
  "Broadcast an issue update to all clients."
  (ws-broadcast (cl-json:encode-json-to-string
                 `((:type . "issue-update")
                   (:data . ,(plist-to-json issue))))))

(defun ws-broadcast-issue-created (issue)
  "Broadcast a new issue to all clients."
  (ws-broadcast (cl-json:encode-json-to-string
                 `((:type . "issue-created")
                   (:data . ,(plist-to-json issue))))))

(defun ws-broadcast-issue-deleted (issue-id)
  "Broadcast issue deletion to all clients."
  (ws-broadcast (cl-json:encode-json-to-string
                 `((:type . "issue-deleted")
                   (:id . ,issue-id)))))

(defun ws-broadcast-comment-created (comment issue-id)
  "Broadcast a new comment to all clients."
  (ws-broadcast (cl-json:encode-json-to-string
                 `((:type . "comment-created")
                   (:issue-id . ,issue-id)
                   (:data . ,(plist-to-json comment))))))

;;; WebSocket upgrade handler

(defun handle-ws-upgrade (env)
  "Handle WebSocket upgrade. Returns a Clack responder."
  (let* ((ws (websocket-driver:make-server env))
         (id (format nil "~a" (get-universal-time))))
    (ws-add-connection id ws)
    (websocket-driver:on :open ws
      (lambda ()
        (bl:info "WebSocket connected: ~a" id)))
    (websocket-driver:on :message ws
      (lambda (data)
        (bl:info "WS message: ~a" data)))
    (websocket-driver:on :close ws
      (lambda (&key code reason)
        (bl:info "WebSocket disconnected: ~a (~a ~a)" id code reason)
        (ws-remove-connection id)))
    (lambda (responder)
      (declare (ignore responder))
      (websocket-driver:start-connection ws))))
