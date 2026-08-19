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

;;; Minimal TCP nREPL server

(defvar *nrepl-server* nil)
(defvar *nrepl-port* nil)

(defun nrepl-eval-and-print (expr stream)
  "Evaluate EXPR and write the result to STREAM."
  (handler-case
      (bind ((result (eval expr))
             (output (format nil "~s~%" result)))
        (write-string output stream)
        (force-output stream))
    (error (e)
      (bind ((output (format nil "ERROR: ~a~%" e)))
        (write-string output stream)
        (force-output stream)))))

(defun nrepl-read-respond (stream)
  "Read one line from STREAM and respond. Returns NIL on EOF; errors are
   reported but do not end the client session."
  (let ((line (read-line stream nil nil)))
    (when line
      (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) line)))
        (when (> (length trimmed) 0)
          (handler-case
              (let ((result (eval (read-from-string trimmed))))
                (format stream "~s~%" result)
                (force-output stream))
            (error (e)
              (ignore-errors (format stream "ERROR: ~a~%" e)))))
t))))

(defun nrepl-handle-client (stream)
  "Handle a single nREPL client connection."
  (unwind-protect
      (iter (while (handler-case
                       (progn
                         (write-string "nREPL> " stream)
                         (force-output stream)
                         (nrepl-read-respond stream))
                     (error (e)
                       (ignore-errors (format stream "ERROR: ~a~%" e))
                       nil))))
    (ignore-errors (close stream))))

(defun start-nrepl (port &key (interface "127.0.0.1"))
  "Start nREPL server on PORT bound to INTERFACE."
  (bind ((socket (usocket:socket-listen interface port
                                        :backlog 5
                                        :reuse-address t)))
    (setf *nrepl-server* socket
          *nrepl-port* port)
    ;; Accept connections in background
    (bt:make-thread
     (lambda ()
       (iter (while t)
         (handler-case
              (bind ((client (usocket:socket-accept socket)))
               (bt:make-thread
                (lambda ()
                  (nrepl-handle-client (usocket:socket-stream client)))
                :name (format nil "nrepl-client-~a"
                              (usocket:get-peer-address client))))
           (error (e)
             (bl:error "nREPL accept error: ~a" e)))))
     :name "nrepl-acceptor")
    (bl:info "nREPL on ~a:~a" interface port)))

(defun stop-nrepl ()
  "Stop the nREPL server."
  (when *nrepl-server*
    (ignore-errors (usocket:socket-close *nrepl-server*))
    (setf *nrepl-server* nil
          *nrepl-port* nil)))
