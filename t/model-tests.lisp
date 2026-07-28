(in-package :focus/tests)

(in-suite focus-tests)

(test create-and-get-user
  (let ((id (focus::create-user "testuser" "test@example.com")))
    (is (numberp id))
    (let ((user (focus::get-user-by-id id)))
      (is (string= "testuser" (getf user :username)))
      (is (string= "test@example.com" (getf user :email))))))

(test create-and-get-ticket
  (let ((id (focus::create-ticket "Test Issue" :description "Description" :priority "high")))
    (is (numberp id))
    (let ((ticket (focus::get-ticket-by-id id)))
      (is (string= "Test Issue" (getf ticket :title)))
      (is (string= "high" (getf ticket :priority))))))

(test list-tickets
  (let ((tickets (focus::list-tickets)))
    (is (listp tickets))))

(test create-and-get-label
  (let ((id (focus::create-label "test-label" :color "#ff0000")))
    (is (numberp id))
    (let ((label (focus::get-label-by-id id)))
      (is (string= "test-label" (getf label :name)))
      (is (string= "#ff0000" (getf label :color))))))

(test ticket-labels
  (let ((ticket-id (focus::create-ticket "Label Test"))
        (label-id (focus::create-label "test-label")))
    (focus::add-label-to-ticket ticket-id label-id)
    (let ((labels (focus::get-ticket-labels ticket-id)))
      (is (= 1 (length labels))))))

(test create-and-get-comment
  (let* ((ticket-id (focus::create-ticket "Comment Test"))
         (user-id (focus::create-user "commenter" "c@test.com"))
         (comment-id (focus::create-comment ticket-id user-id "Hello")))
    (is (numberp comment-id))
    (let ((comment (focus::get-comment-by-id comment-id)))
      (is (string= "Hello" (getf comment :body))))))
