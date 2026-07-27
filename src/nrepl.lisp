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

(defun nrepl-handle-client (stream)
  "Handle a single nREPL client connection."
  (unwind-protect
      (iter (while t)
        (write-string "nREPL> " stream)
        (force-output stream)
        (bind ((line (read-line stream nil nil)))
          (unless line (return nil))
          (bind ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) line)))
            (when (> (length trimmed) 0)
              (handler-case
                  (bind ((expr (read-from-string trimmed))
                         (result (eval expr)))
                    (format stream "~s~%" result)
                    (force-output stream))
                (error (e)
                  (format stream "ERROR: ~a~%" e)
                  (force-output stream)))))))
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
