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

(in-package :focus)

;;; Static file serving

(defun guess-content-type (path)
  "Guess content type from file extension."
  (let ((ext (pathname-type (pathname path))))
    (cond
      ((string= ext "html") "text/html")
      ((string= ext "css") "text/css")
      ((string= ext "js") "application/javascript")
      ((string= ext "json") "application/json")
      ((string= ext "png") "image/png")
      ((string= ext "jpg") "image/jpeg")
      ((string= ext "svg") "image/svg+xml")
      ((string= ext "ico") "image/x-icon")
      (t "application/octet-stream"))))

(defun serve-static-file (path)
  "Serve a static file embedded in the binary image."
  (let* ((rel-path (if (and (plusp (length path))
                            (char= (char path 0) #\/))
                       (subseq path 1)
                       path))
         (content (static-asset-bytes rel-path)))
    (if content
        (list 200
              `(:content-type ,(guess-content-type path)
                :content-length ,(length content)
                :cache-control ,(if (string= rel-path "index.html")
                                    "no-cache"
                                    "max-age=3600"))
              (list content))
        nil)))

;;; API Router

(defun router (env)
  "Route requests to handlers."
  (bind ((path (getf env :path-info))
         (method (getf env :request-method)))
    (cond
      ;; API routes
      ((ppcre:scan "^/api/" path)
       (route-api env path method))
      ;; Static files
       ((and (string= method "GET"))
        (or (serve-static-file path)
            (and (ppcre:scan "^/tickets/\\d+$" path)
                 (serve-static-file "index.html"))
            (and (ppcre:scan "^/tickets/\\d+/activity$" path)
                 (serve-static-file "index.html"))
(and (string= path "/")
                  (serve-static-file "index.html"))
             (and (string= path "/activity")
                  (serve-static-file "index.html"))
             (and (string= path "/settings")
                 (serve-static-file "index.html"))
            (and (ppcre:scan "^/boards/\\d+$" path)
                 (serve-static-file "index.html"))
            (and (ppcre:scan "^/boards/\\d+/activity$" path)
                 (serve-static-file "index.html"))
            (error-response "Not found" 404)))
      ;; 404
      (t
       (error-response "Not found" 404)))))

(defun route-auth (env path method)
  "Auth, app info, and the agent envelope endpoint."
  (cond
    ((and (string= path "/api/auth/login")
          (string= method "GET"))
     (handle-auth-login env))
    ((and (string= path "/api/auth/callback")
          (string= method "GET"))
     (handle-auth-callback env))
    ((and (string= path "/api/auth/me")
          (string= method "GET"))
     (handle-auth-me env))
    ((and (string= path "/api/auth/logout")
          (string= method "POST"))
     (handle-auth-logout env))
    ((and (string= path "/api/app/info")
          (string= method "GET"))
     (handle-app-info env))
    ;; Agent envelope (bearer-authenticated inside)
    ((and (string= path "/api/agent")
          (string= method "POST"))
     (handle-agent-envelope env))
    (t nil)))

(defun route-tickets (env path method)
  "Tickets CRUD and search."
  (cond
    ((and (string= path "/api/tickets")
          (string= method "GET"))
     (handle-list-tickets env))
    ((and (string= path "/api/tickets")
          (string= method "POST"))
     (handle-create-ticket env))
    ;; Search must come before parameterized routes
    ((and (string= method "GET")
          (ppcre:scan "^/api/tickets/search" path))
     (handle-search-tickets env))
    ;; Ticket by ID (GET/PUT/DELETE)
    ((and (string= method "GET")
          (ppcre:scan "^/api/tickets/\\d+$" path))
     (handle-get-ticket env))
    ((and (string= method "PUT")
          (ppcre:scan "^/api/tickets/\\d+$" path))
     (handle-update-ticket env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/tickets/\\d+$" path))
     (handle-delete-ticket env))
    (t nil)))

(defun route-ticket-details (env path method)
  "Ticket comments, labels, activity, and observers."
  (cond
    ;; Comments
    ((and (string= method "GET")
          (ppcre:scan "^/api/tickets/\\d+/comments$" path))
     (handle-list-comments env))
    ((and (string= method "POST")
          (ppcre:scan "^/api/tickets/\\d+/comments$" path))
     (handle-create-comment env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/tickets/\\d+/comments/\\d+$" path))
     (handle-delete-comment env))
    ;; Ticket labels
    ((and (string= method "GET")
          (ppcre:scan "^/api/tickets/\\d+/labels$" path))
     (handle-list-ticket-labels env))
    ((and (string= method "POST")
          (ppcre:scan "^/api/tickets/\\d+/labels/\\w+$" path))
     (handle-add-ticket-label env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/tickets/\\d+/labels/\\w+$" path))
     (handle-remove-ticket-label env))
    ;; Activity
    ((and (string= method "GET")
          (ppcre:scan "^/api/tickets/\\d+/activity$" path))
     (handle-list-activity env))
    ;; Ticket observers
    ((and (string= method "GET")
          (ppcre:scan "^/api/tickets/\\d+/observers$" path))
     (handle-list-ticket-observers env))
    ((and (string= method "POST")
          (ppcre:scan "^/api/tickets/\\d+/observers$" path))
     (handle-add-ticket-observer env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/tickets/\\d+/observers/.+$" path))
     (handle-remove-ticket-observer env))
    (t nil)))

(defun route-users (env path method)
  "Users."
  (cond
    ((and (string= path "/api/users")
          (string= method "GET"))
     (handle-list-users env))
    ((and (string= path "/api/users")
          (string= method "POST"))
     (handle-create-user env))
    ((and (string= method "PUT")
          (ppcre:scan "^/api/users/\\d+$" path))
     (handle-update-user env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/users/\\d+$" path))
     (handle-delete-user env))
    ((and (string= method "POST")
          (ppcre:scan "^/api/users/\\d+/undelete$" path))
     (handle-undelete-user env))
    (t nil)))

(defun route-labels-webhooks (env path method)
  "Labels and webhooks."
  (cond
    ((and (string= path "/api/labels")
          (string= method "GET"))
     (handle-list-labels env))
    ((and (string= path "/api/labels")
          (string= method "POST"))
     (handle-create-label env))
    ;; Attachments
    ((and (string= method "GET")
          (ppcre:scan "^/api/attachments/\\d+$" path))
     (handle-get-attachment env))
    ((and (string= path "/api/webhooks")
          (string= method "GET"))
     (handle-list-webhooks env))
    ((and (string= path "/api/webhooks")
          (string= method "POST"))
     (handle-create-webhook env))
    (t nil)))

(defun route-groups (env path method)
  "Groups and their members."
  (cond
    ((and (string= path "/api/groups")
          (string= method "GET"))
     (handle-list-groups env))
    ((and (string= path "/api/groups")
          (string= method "POST"))
     (handle-create-group env))
    ((and (string= method "GET")
          (ppcre:scan "^/api/groups/\\d+$" path))
     (handle-get-group env))
    ((and (string= method "PUT")
          (ppcre:scan "^/api/groups/\\d+$" path))
     (handle-update-group env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/groups/\\d+$" path))
     (handle-delete-group env))
    ((and (string= method "GET")
          (ppcre:scan "^/api/groups/\\d+/members$" path))
     (handle-list-group-members env))
    ((and (string= method "POST")
          (ppcre:scan "^/api/groups/\\d+/members$" path))
     (handle-add-group-member env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/groups/\\d+/members/\\d+$" path))
     (handle-remove-group-member env))
    (t nil)))

(defun route-boards (env path method)
  "Boards CRUD and combined activity."
  (cond
    ;; Combined activity across all visible boards
    ((and (string= path "/api/activity")
          (string= method "GET"))
     (handle-list-all-board-activity env))
    ((and (string= path "/api/boards")
          (string= method "GET"))
     (handle-list-boards env))
    ((and (string= path "/api/boards")
          (string= method "POST"))
     (handle-create-board env))
    ((and (string= method "GET")
          (ppcre:scan "^/api/boards/\\d+$" path))
     (handle-get-board env))
    ((and (string= method "PUT")
          (ppcre:scan "^/api/boards/\\d+$" path))
     (handle-update-board env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/boards/\\d+$" path))
     (handle-delete-board env))
    (t nil)))

(defun route-board-details (env path method)
  "Board activity, transitions, statuses, and members."
  (cond
    ((and (string= method "GET")
          (ppcre:scan "^/api/boards/\\d+/activity$" path))
     (handle-list-board-activity env))
    ((and (string= method "GET")
          (ppcre:scan "^/api/boards/\\d+/transitions$" path))
     (handle-list-board-transitions env))
    ((and (string= method "POST")
          (ppcre:scan "^/api/boards/\\d+/transitions$" path))
     (handle-add-board-transition env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/boards/\\d+/transitions/.+$" path))
     (handle-remove-board-transition env))
    ((and (string= method "GET")
          (ppcre:scan "^/api/boards/\\d+/statuses$" path))
     (handle-list-board-statuses env))
    ((and (string= method "POST")
          (ppcre:scan "^/api/boards/\\d+/statuses$" path))
     (handle-create-board-status env))
    ((and (string= method "PUT")
          (ppcre:scan "^/api/boards/\\d+/statuses/\\d+$" path))
     (handle-update-board-status env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/boards/\\d+/statuses/\\d+$" path))
     (handle-delete-board-status env))
    ((and (string= method "GET")
          (ppcre:scan "^/api/boards/\\d+/members$" path))
     (handle-list-board-members env))
    ((and (string= method "POST")
          (ppcre:scan "^/api/boards/\\d+/members$" path))
     (handle-add-board-member env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/boards/\\d+/members/.+$" path))
     (handle-remove-board-member env))
    (t nil)))

(defun route-agents (env path method)
  "Agents and their credential shapes."
  (cond
    ((and (string= path "/api/agents")
          (string= method "GET"))
     (handle-list-agents env))
    ((and (string= path "/api/agents")
          (string= method "POST"))
     (handle-create-agent env))
    ((and (string= method "GET")
          (ppcre:scan "^/api/agents/\\d+/shapes$" path))
     (handle-list-agent-shapes env))
    ((and (string= method "POST")
          (ppcre:scan "^/api/agents/\\d+/shapes$" path))
     (handle-create-agent-shape env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/agents/\\d+/shapes/\\d+$" path))
     (handle-revoke-agent-shape env))
    ((and (string= method "GET")
          (ppcre:scan "^/api/agents/\\d+$" path))
     (handle-get-agent env))
    ((and (string= method "PUT")
          (ppcre:scan "^/api/agents/\\d+$" path))
     (handle-update-agent env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/agents/\\d+$" path))
     (handle-delete-agent env))
    (t nil)))

(defun route-api (env path method)
  "Route API requests through per-resource routers."
  (or (route-auth env path method)
      (route-tickets env path method)
      (route-ticket-details env path method)
      (route-users env path method)
      (route-labels-webhooks env path method)
      (route-groups env path method)
      (route-boards env path method)
      (route-board-details env path method)
      (route-agents env path method)
      (error-response "Not found" 404)))
