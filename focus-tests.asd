(defsystem :focus-tests
  :name "focus-tests"
  :description "Tests for focus"
  :depends-on (#:focus
               #:fiveam)
  :serial t
  :components ((:module "t"
                :components ((:file "package")
                             (:file "api-tests")
                             (:file "model-tests")
                             (:file "cli-tests")))))
