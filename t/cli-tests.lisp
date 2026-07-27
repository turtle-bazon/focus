(in-package :focus/tests)

(in-suite focus-tests)

(test parse-args-rebuild-db
  (let ((result (focus::parse-args '("focus" "--rebuild-db"))))
    (is (getf result :rebuild-db))))

(test parse-args-empty
  (let ((result (focus::parse-args '("focus"))))
    (is (null result))))
