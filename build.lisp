(defparameter *project-name* "focus")

(defun build-suffix ()
  (or (uiop:getenv "BUILD_SUFFIX") ""))

(push :binary *features*)
(push (merge-pathnames #P"internal-libs/cl-oauth2/"
                       *default-pathname-defaults*)
      asdf:*central-registry*)
(ql:quickload *project-name*)
(ensure-directories-exist "build")
(sb-ext:save-lisp-and-die (format nil "build/~a~a" *project-name* (build-suffix))
                          :toplevel (find-symbol "MAIN" (find-package (string-upcase *project-name*)))
                          :executable t)
