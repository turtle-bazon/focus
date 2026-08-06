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

(in-package :focus/tests)

(in-suite focus-tests)

(test root-command-builds
  (let ((cmd (focus::make-root-command)))
    (is (string= (clingon:command-name cmd) "focus"))
    (is (= 4 (length (clingon:command-sub-commands cmd))))))

(test root-command-has-rebuild-db-option
  (find-if (lambda (opt)
             (eq (clingon:option-key opt) :rebuild-db))
           (clingon:command-options (focus::make-root-command))))
