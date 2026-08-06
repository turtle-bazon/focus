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

(defun ws-broadcast-ticket-update (ticket)
  "Broadcast a ticket update to all clients."
  (ws-broadcast (cl-json:encode-json-to-string
                 `((:type . "ticket-update")
                   (:data . ,(plist-to-json ticket))))))

(defun ws-broadcast-ticket-created (ticket)
  "Broadcast a new ticket to all clients."
  (ws-broadcast (cl-json:encode-json-to-string
                 `((:type . "ticket-created")
                   (:data . ,(plist-to-json ticket))))))

(defun ws-broadcast-ticket-deleted (ticket-id)
  "Broadcast ticket deletion to all clients."
  (ws-broadcast (cl-json:encode-json-to-string
                 `((:type . "ticket-deleted")
                   (:id . ,ticket-id)))))

(defun ws-broadcast-comment-created (comment ticket-id)
  "Broadcast a new comment to all clients."
  (ws-broadcast (cl-json:encode-json-to-string
                 `((:type . "comment-created")
                   (:ticket-id . ,ticket-id)
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
