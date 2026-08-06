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

(defparameter *project-name* "focus")

(push :binary *features*)
(push (merge-pathnames #P"internal-libs/cl-oauth2/"
                       *default-pathname-defaults*)
      asdf:*central-registry*)
(ql:quickload *project-name*)
(ensure-directories-exist "build")
(asdf:make *project-name*)
(let ((suffix (uiop:getenv "BUILD_SUFFIX")))
  (when (and suffix (plusp (length suffix)))
    (rename-file #P"build/focus" (format nil "build/focus~a" suffix))))
