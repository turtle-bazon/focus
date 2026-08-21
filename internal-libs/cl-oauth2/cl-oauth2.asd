(defsystem :cl-oauth2
  :name "cl-oauth2"
  :version "0.1.0"
  :description "OAuth2 / OpenID Connect client for Common Lisp"
  :depends-on (#:dexador
               #:com.inuoe.jzon
               #:ironclad
               #:cl-base64
               #:split-sequence
               #:bordeaux-threads
               #:iterate)
  :serial t
  :components ((:module "src"
                :components ((:file "package")
                             (:file "core")
                             (:file "jwt")
                             (:file "flows")
                             (:file "session")))))
