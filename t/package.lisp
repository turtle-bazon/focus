(defpackage :focus/tests
  (:use :cl :fiveam :focus)
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
    (focus::disconnect-db)))
