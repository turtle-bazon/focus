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
  "Serve a static file from the configured static directory."
  (let* ((rel-path (if (and (plusp (length path))
                            (char= (char path 0) #\/))
                       (subseq path 1)
                       path))
         (root (config->static-dir *config*))
         (full-path (merge-pathnames rel-path root)))
    (if (and (probe-file full-path)
             (not (uiop:directory-pathname-p full-path)))
        (let ((content (with-open-file (s full-path :direction :input :element-type '(unsigned-byte 8))
                         (let ((data (make-array (file-length s) :element-type '(unsigned-byte 8))))
                           (read-sequence data s)
                           data))))
          (list 200
                `(:content-type ,(guess-content-type path)
                  :content-length ,(length content))
                (list content)))
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
           (serve-static-file (if (string= path "/") "index.html" path))
           (error-response "Not found" 404)))
      ;; 404
      (t
       (error-response "Not found" 404)))))

(defun route-api (env path method)
  "Route API requests."
  (cond
    ;; Issues - list and create (exact path)
    ((and (string= path "/api/issues")
          (string= method "GET"))
     (handle-list-issues env))
    ((and (string= path "/api/issues")
          (string= method "POST"))
     (handle-create-issue env))
    ;; Search must come before parameterized routes
    ((and (string= method "GET")
          (ppcre:scan "^/api/issues/search" path))
     (handle-search-issues env))
    ;; Issue by ID (GET/PUT/DELETE)
    ((and (string= method "GET")
          (ppcre:scan "^/api/issues/\\d+$" path))
     (handle-get-issue env))
    ((and (string= method "PUT")
          (ppcre:scan "^/api/issues/\\d+$" path))
     (handle-update-issue env))
    ((and (string= method "DELETE")
          (ppcre:scan "^/api/issues/\\d+$" path))
     (handle-delete-issue env))
    ;; Comments
    ((and (string= method "GET")
          (ppcre:scan "^/api/issues/\\d+/comments$" path))
     (handle-list-comments env))
    ((and (string= method "POST")
          (ppcre:scan "^/api/issues/\\d+/comments$" path))
     (handle-create-comment env))
    ;; Activity
    ((and (string= method "GET")
          (ppcre:scan "^/api/issues/\\d+/activity$" path))
     (handle-list-activity env))
    ;; Users
    ((and (string= path "/api/users")
          (string= method "GET"))
     (handle-list-users env))
    ((and (string= path "/api/users")
          (string= method "POST"))
     (handle-create-user env))
    ;; Labels
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
    ;; Webhooks
    ((and (string= path "/api/webhooks")
          (string= method "GET"))
     (handle-list-webhooks env))
    ((and (string= path "/api/webhooks")
          (string= method "POST"))
     (handle-create-webhook env))
    ;; 404
    (t
     (error-response "Not found" 404))))

(defun extract-id-from-path (path)
  "Extract numeric ID from path like /api/issues/123."
  (ppcre:register-groups-bind (id)
      ("^/api/(?:issues|attachments|users|labels|webhooks)/(\\d+)$" path)
    (when id (parse-integer id))))
