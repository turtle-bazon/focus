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
         (names (iter (for cmd in (clingon:command-sub-commands agent))
                  (collecting (clingon:command-name cmd)))))
    (is (member "init" names :test #'string=))
    (is (member "use" names :test #'string=))))

(test remote-command-builds
  (let ((cmd (focus::make-remote-root-command)))
    (is (string= (clingon:command-name cmd) "focus-cli"))
    (is (= 11 (length (clingon:command-sub-commands cmd))))
    (iter (for name in '("add-site" "add-board" "list-sites" "list-boards" "list"
                         "show" "create" "update" "delete" "comment" "label"))
      (is (find-if (lambda (sub) (string= name (clingon:command-name sub)))
                   (clingon:command-sub-commands cmd))
          "focus-cli should have ~a subcommand" name))
    (is (null (find-if (lambda (sub) (string= "configure" (clingon:command-name sub)))
                       (clingon:command-sub-commands cmd))))
    (is (null (find-if (lambda (sub) (string= "status" (clingon:command-name sub)))
                       (clingon:command-sub-commands cmd))))))

(test remote-json-decoder-normalizes-keys
  (let* ((decoded (focus::json->
                   (jzon:parse
                    "{\"tickets\":[{\"id\":1,\"title\":\"x\",\"assignee_id\":5,\"is_default\":true}]}"))))
    (let ((ticket (car (getf decoded :tickets))))
      (is (= 1 (getf ticket :id)))
      (is (= 5 (getf ticket :assignee-id)))
      (is (eq t (getf ticket :is-default))))))

(defun with-test-config (config thunk)
  "Run THUNK with the CLI config path pointed at a temp copy of CONFIG."
  (let ((focus::+focus-cli-config-path+
          (merge-pathnames #P".focus-cli-test" (user-homedir-pathname))))
    (focus::write-cli-config-file config)
    (unwind-protect (funcall thunk)
      (when (probe-file focus::+focus-cli-config-path+)
        (delete-file focus::+focus-cli-config-path+)))))

(test legacy-config-wraps-as-default-site
  (with-test-config '(:server-url "http://x:8080" :key "focus1-abc" :board-id 3)
    (lambda ()
      (let ((loaded (focus::read-cli-config)))
        (is (= 1 (length (getf loaded :sites))))
        (is (string= "default" (caar (getf loaded :sites))))
        (is (string= "http://x:8080"
                     (getf (cdar (getf loaded :sites)) :server-url)))))))

(test current-format-normalizes-to-sites
  (with-test-config '(:current "work"
                      :sites (("home" :server-url "http://h:8080" :key "focus1-a" :board-id 1)
                              ("work" :server-url "http://w:8080" :key "focus2-b" :board-id 2)))
    (lambda ()
      (let ((loaded (focus::read-cli-config)))
        (is (null (getf loaded :current)))
        (is (= 2 (length (getf loaded :sites))))
        (is (string= "http://w:8080"
                     (getf (focus::cli-site-config "work") :server-url)))))))

(test multi-site-config-reads-sites
  (with-test-config '(:sites (("home" :server-url "http://h:8080" :key "focus1-a" :board-id 1)
                              ("work" :server-url "http://w:8080" :key "focus2-b" :board-id 2)))
    (lambda ()
      (is (equal '("home" "work") (focus::cli-site-names)))
      (is (string= "http://h:8080"
                   (getf (focus::cli-site-config "home") :server-url)))
      (is (= 2 (getf (focus::cli-site-config "work") :board-id))))))

(test add-site-stores-server-key-and-preserves-boards
  (with-test-config '(:sites (("work" :server-url "http://w:8080" :bearer "focus2-b"
                                         :boards (("hd" . "Helpdesk")))))
    (lambda ()
      (focus::cli-add-site "work" "http://new:8080" "focus3-c" "srv-pub" "agt-priv")
      (let ((config (focus::cli-site-config "work")))
        (is (string= "http://new:8080" (getf config :server-url)))
        (is (string= "focus3-c" (getf config :bearer)))
        (is (string= "srv-pub" (getf config :server-public)))
        (is (string= "agt-priv" (getf config :agent-private))))
      (is (string= "Helpdesk" (focus::cli-local-board-remote "work" "hd"))))))

(test board-alias-maps-local-to-remote
  (with-test-config '(:sites (("work" :server-url "http://w:8080" :key "focus2-b")))
    (lambda ()
      (focus::cli-set-site-board "work" "hd" "Helpdesk")
      (is (string= "Helpdesk" (focus::cli-local-board-remote "work" "hd")))
      (focus::cli-set-site-board "work" "hd" "Queue")
      (is (= 1 (length (focus::cli-site-boards "work"))))
      (is (string= "Queue" (focus::cli-local-board-remote "work" "hd"))))))

(test site-scoped-commands-take-site-option
  (iter (for sub in (clingon:command-sub-commands (focus::make-remote-root-command)))
    (when (member (clingon:command-name sub)
                  '("show" "update" "delete" "add-board" "list-boards")
                  :test #'string=)
      (is (find-if (lambda (opt) (eq (clingon:option-key opt) :site))
                   (clingon:command-options sub))
          "~a should take --site" (clingon:command-name sub)))))

(test board-spec-splits-site-and-board
  (multiple-value-bind (board site) (focus::split-board-spec "work/helpdesk")
    (is (string= "helpdesk" board))
    (is (string= "work" site)))
  (multiple-value-bind (board site) (focus::split-board-spec "helpdesk")
    (is (string= "helpdesk" board))
    (is (null site)))
  (multiple-value-bind (board site) (focus::split-board-spec "7")
    (is (string= "7" board))
    (is (null site))))

(test remote-commands-take-board-env
  (iter (for name in '("list" "create"))
    (let* ((root (focus::make-remote-root-command))
           (sub (find-if (lambda (c) (string= name (clingon:command-name c)))
                         (clingon:command-sub-commands root)))
           (opt (find-if (lambda (o) (eq (clingon:option-key o) :board))
                         (clingon:command-options sub))))
      (is-true opt "~a should have a --board option" name)
      (is (member "FOCUS_BOARD" (clingon:option-env-vars opt) :test #'string=)))))

(test split-words-splits-on-spaces-and-commas
  (is (equal '("2" "4") (focus::split-words "2 4")))
  (is (equal '("Deploy" "Work" "7") (focus::split-words "Deploy, Work 7"))))
