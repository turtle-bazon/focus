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

;;; WebSocket connections — each connection knows its owner so broadcasts can
;;; be filtered by board membership.

(defvar *ws-connections* (make-hash-table :test 'equal))
(defvar *ws-lock* (bt:make-lock "ws-connections"))

(defvar *ws-notifier* nil)
(defvar *ws-event-loop-thread* nil)
(defvar *ws-pending* nil)
(defvar *ws-pending-lock* (bt:make-lock "ws-pending"))

(defun ws-drain-pending ()
  "Flush queued sends on the event-loop thread."
  (let ((pending (bt:with-lock-held (*ws-pending-lock*)
                   (prog1 *ws-pending*
                     (setf *ws-pending* nil)))))
    (iter (for item in pending)
          (funcall item))))

(defun ws-ensure-notifier ()
  "Return the event-loop notifier used to marshal sends from foreign threads.
   Must be called on the event-loop thread."
  (or *ws-notifier*
      (setf *ws-notifier*
            (cl-async:make-notifier #'ws-drain-pending :single-shot nil)
            *ws-event-loop-thread* (bt:current-thread))))

(defun ws-send-on-thread (id connection message)
  "Send MESSAGE to CONNECTION, removing the connection on error."
  (handler-case
      (websocket-driver:send connection message)
    (error ()
      (ws-remove-connection id))))

(defun ws-send (id entry message)
  "Send MESSAGE to the WebSocket of ENTRY, removing the connection on error.
   When called from a thread other than the cl-async event loop, the send is
   marshalled onto the loop via a notifier."
  (if (and *ws-notifier*
           (not (eq *ws-event-loop-thread* (bt:current-thread))))
      (bt:with-lock-held (*ws-pending-lock*)
        (push (lambda ()
                (ws-send-on-thread id (first entry) message))
              *ws-pending*)
        (cl-async:trigger-notifier *ws-notifier*))
      (ws-send-on-thread id (first entry) message)))

(defun ws-add-connection (id connection user-id)
  "Add a WebSocket connection."
  (ws-ensure-notifier)
  (bt:with-lock-held (*ws-lock*)
    (setf (gethash id *ws-connections*) (list connection user-id))))

(defun ws-remove-connection (id)
  "Remove a WebSocket connection."
  (bt:with-lock-held (*ws-lock*)
    (remhash id *ws-connections*)))

(defun ws-user-id (entry)
  "User ID of a stored connection entry."
  (second entry))

(defun ws-broadcast (message &optional to-board)
  "Broadcast a message to connected clients. When TO-BOARD is given, only
   clients who may view that board receive it."
  (bt:with-lock-held (*ws-lock*)
    (maphash (lambda (id entry)
               (when (or (null to-board)
                         (user-can-view-board to-board (ws-user-id entry)))
                 (ws-send id entry message)))
             *ws-connections*)))

(defun ws-broadcast-ticket-update (ticket)
  "Broadcast a ticket update to clients who can see its board."
  (ws-broadcast
   (cl-json:encode-json-to-string
    (plist-to-json
     `(:type "ticket-update"
       :board_id ,(getf ticket :board-id)
       :data ,ticket)))
   (getf ticket :board-id)))

(defun ws-broadcast-ticket-created (ticket)
  "Broadcast a new ticket to clients who can see its board."
  (ws-broadcast
   (cl-json:encode-json-to-string
    (plist-to-json
     `(:type "ticket-created"
       :board_id ,(getf ticket :board-id)
       :data ,ticket)))
   (getf ticket :board-id)))

(defun ws-broadcast-ticket-deleted (ticket)
  "Broadcast ticket deletion to clients who can see its board."
  (ws-broadcast
   (cl-json:encode-json-to-string
    (plist-to-json
     `(:type "ticket-deleted"
       :id ,(getf ticket :id)
       :board_id ,(getf ticket :board-id))))
   (getf ticket :board-id)))

(defun ws-broadcast-comment-created (comment ticket-id ticket-board)
  "Broadcast a new comment to clients who can see the ticket's board."
  (ws-broadcast
   (cl-json:encode-json-to-string
    `((:type . "comment-created")
      (:ticket-board ,ticket-board)
      (:ticket-id ,ticket-id)
      (:data . ,(plist-to-json comment))))
   ticket-board))

(defun ws-broadcast-activity-created (activity)
  "Broadcast a new activity entry to clients who can see its board.
   ACTIVITY is a plist with at least :ticket_id and :board_id."
  (ws-broadcast
   (cl-json:encode-json-to-string
    `((:type . "activity-created")
      (:data . ,(plist-to-json activity))))
   (getf activity :board_id)))

;;; WebSocket upgrade handler

(defun handle-ws-upgrade (env)
  "Handle WebSocket upgrade. Returns a Clack responder."
  (let* ((ws (websocket-driver:make-server env))
         (id (format nil "~a-~a" (get-universal-time) (random 100000)))
         (user-id (get-user-id-from-env env)))
    (when (null user-id)
      (return-from handle-ws-upgrade
        (list "Unauthorized"
              '(:content-type "text/plain")
              '())))
    (ws-add-connection id ws user-id)
    (websocket-driver:on :open ws
      (lambda ()
        (bl:info "WebSocket connected: ~a (user ~a)" id user-id)))
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