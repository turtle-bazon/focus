(in-package :focus/tests)

(in-suite focus-tests)

(test create-and-get-user
  (let ((id (focus::create-user "testuser" "test@example.com")))
    (is (numberp id))
    (let ((user (focus::get-user-by-id id)))
      (is (string= "testuser" (getf user :username)))
      (is (string= "test@example.com" (getf user :email))))))

(test create-and-get-issue
  (let ((id (focus::create-issue "Test Issue" :description "Description" :priority "high")))
    (is (numberp id))
    (let ((issue (focus::get-issue-by-id id)))
      (is (string= "Test Issue" (getf issue :title)))
      (is (string= "high" (getf issue :priority))))))

(test list-issues
  (let ((issues (focus::list-issues)))
    (is (listp issues))))

(test create-and-get-label
  (let ((id (focus::create-label "test-label" :color "#ff0000")))
    (is (numberp id))
    (let ((label (focus::get-label-by-id id)))
      (is (string= "test-label" (getf label :name)))
      (is (string= "#ff0000" (getf label :color))))))

(test issue-labels
  (let ((issue-id (focus::create-issue "Label Test"))
        (label-id (focus::create-label "test-label")))
    (focus::add-label-to-issue issue-id label-id)
    (let ((labels (focus::get-issue-labels issue-id)))
      (is (= 1 (length labels))))))

(test create-and-get-comment
  (let* ((issue-id (focus::create-issue "Comment Test"))
         (user-id (focus::create-user "commenter" "c@test.com"))
         (comment-id (focus::create-comment issue-id user-id "Hello")))
    (is (numberp comment-id))
    (let ((comment (focus::get-comment-by-id comment-id)))
      (is (string= "Hello" (getf comment :body))))))
