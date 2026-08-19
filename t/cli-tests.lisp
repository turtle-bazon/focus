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
    (is (= 11 (length (clingon:command-sub-commands cmd))))))

(test root-command-has-rebuild-db-option
  (find-if (lambda (opt)
             (eq (clingon:option-key opt) :rebuild-db))
           (clingon:command-options (focus::make-root-command))))

(test root-command-has-management-groups
  (let ((subs (clingon:command-sub-commands (focus::make-root-command))))
    (is (find-if (lambda (cmd) (string= "comment" (clingon:command-name cmd))) subs))
    (is (find-if (lambda (cmd) (string= "label" (clingon:command-name cmd))) subs))
    (is (find-if (lambda (cmd) (string= "agent" (clingon:command-name cmd))) subs))
    (is (find-if (lambda (cmd) (string= "board" (clingon:command-name cmd))) subs))
    (is (find-if (lambda (cmd) (string= "user" (clingon:command-name cmd))) subs))
    (is (find-if (lambda (cmd) (string= "status" (clingon:command-name cmd))) subs))))

(test agent-group-has-setup-commands
  (let* ((root (focus::make-root-command))
         (agent (find-if (lambda (cmd)
                           (string= "agent" (clingon:command-name cmd)))
                         (clingon:command-sub-commands root)))
         (names (mapcar #'clingon:command-name
                        (clingon:command-sub-commands agent))))
    (is (member "init" names :test #'string=))
    (is (member "use" names :test #'string=))))

(test remote-command-builds
  (let ((cmd (focus::make-remote-root-command)))
    (is (string= (clingon:command-name cmd) "focus-cli"))
    (is (= 10 (length (clingon:command-sub-commands cmd))))
    (dolist (name '("configure" "status" "list" "show" "create"
                    "update" "delete" "comment" "label" "board"))
      (is (find-if (lambda (sub) (string= name (clingon:command-name sub)))
                   (clingon:command-sub-commands cmd))
          "focus-cli should have ~a subcommand" name))))

(test remote-json-decoder-normalizes-keys
  (let* ((decoded (focus::json->
                   (cl-json:decode-json-from-string
                    "{\"tickets\":[{\"id\":1,\"title\":\"x\",\"assignee_id\":5,\"is_default\":true}]}"))))
    (let ((ticket (car (getf decoded :tickets))))
      (is (= 1 (getf ticket :id)))
      (is (= 5 (getf ticket :assignee-id)))
      (is (eq t (getf ticket :is-default))))))
