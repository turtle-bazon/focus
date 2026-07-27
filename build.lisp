(defparameter *project-name* "focus")

(defun build-suffix ()
  (or (uiop:getenv "BUILD_SUFFIX") ""))

(push :binary *features*)
(ql:quickload *project-name*)
(ensure-directories-exist "build")
(sb-ext:save-lisp-and-die (format nil "build/~a~a" *project-name* (build-suffix))
                          :toplevel (find-symbol "MAIN" (find-package (string-upcase *project-name*)))
                          :executable t)
