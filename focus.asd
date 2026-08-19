(defsystem :focus
  :name "focus"
  :license "GPL-3.0-or-later"
  :version "0.0.1.3"
  :description "Ticket tracker"
  :depends-on (#:clack
               #:clack-handler-wookie
               #:websocket-driver
               #:cl-json
               #:postmodern
               #:cl-postgres+local-time
               #:iterate
               #:cl-bazon
               #:bazon-log
               #:metabang-bind
               #:clingon
               #:usocket
               #:bordeaux-threads
               #:uiop
               #:dexador
               #:cl-oauth2
               #:cl-base64
               #:ironclad)
  :serial t
  :components ((:module "src"
                :components
                 ((:file "package")
                  (:file "config")
                  (:file "migrations")
                  (:file "static-assets")
                  (:file "static")
                  (:file "db")
                   (:file "nrepl")
                   (:file "ws")
                   (:module "models"
                    :components ((:file "user")
                                  (:file "ticket")
                                 (:file "label")
                                 (:file "comment")
                                 (:file "activity")
                                 (:file "attachment")
                                 (:file "webhook")
                                  (:file "session")
                                  (:file "group")
                                  (:file "ticket-observer")
                                  (:file "board")
                                  (:file "agent")))
                  (:module "api"
                   :components ((:file "routes")
                                (:file "auth")
                                (:file "handlers")))
(:module "cli"
                    :components ((:file "commands")
                                 (:file "remote")))
                   (:file "main"))))
  :build-operation "program-op"
  :build-pathname "build/focus"
  :entry-point "focus:main")
