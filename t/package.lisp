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

(defpackage :focus/tests
  (:use :cl :local-time :iterate :fiveam :focus)
  (:local-nicknames (:jzon :com.inuoe.jzon))
  (:export #:run-focus-tests))

(in-package :focus/tests)

(def-suite focus-tests
  :description "Focus test suite")

(in-suite focus-tests)

(defun cleanup-test-data ()
  (postmodern:execute "DELETE FROM comments WHERE ticket_id IN (SELECT id FROM tickets WHERE title LIKE 'Test%' OR title = 'API Test' OR title = 'Update Test' OR title = 'Delete Test' OR title = 'Searchable Issue' OR title = 'Label Test' OR title = 'Comment Test')")
  (postmodern:execute "DELETE FROM ticket_labels WHERE ticket_id IN (SELECT id FROM tickets WHERE title LIKE 'Test%' OR title = 'API Test' OR title = 'Update Test' OR title = 'Delete Test' OR title = 'Searchable Issue' OR title = 'Label Test' OR title = 'Comment Test')")
  (postmodern:execute "DELETE FROM activity WHERE ticket_id IN (SELECT id FROM tickets WHERE title LIKE 'Test%' OR title = 'API Test' OR title = 'Update Test' OR title = 'Delete Test' OR title = 'Searchable Issue' OR title = 'Label Test' OR title = 'Comment Test')")
  (postmodern:execute "DELETE FROM tickets WHERE title LIKE 'Test%' OR title = 'API Test' OR title = 'Update Test' OR title = 'Delete Test' OR title = 'Searchable Issue' OR title = 'Label Test' OR title = 'Comment Test'")
  (postmodern:execute "DELETE FROM labels WHERE name = 'test-label'")
  (postmodern:execute "DELETE FROM users WHERE username IN ('testuser', 'commenter')"))

(defun run-focus-tests ()
  (unless focus::*db-connection*
    (focus::connect-db '(:db-host "127.0.0.1"
                         :db-name "focus"
                         :db-user "focus"
                         :db-pass "focus")))
  (cleanup-test-data)
  (fiveam:run! 'focus-tests)
  (cleanup-test-data)
  (when focus::*db-connection*
    (focus::disconnect-db))
  t)
