(in-package :focus/tests)

(in-suite focus-tests)

(test create-ticket-via-model
  (let ((id (focus::create-ticket "API Test" :description "Testing" :priority "high")))
    (is (numberp id))
    (let ((ticket (focus::get-ticket-by-id id)))
      (is (string= "API Test" (getf ticket :title))))))

(test update-ticket-via-model
  (let* ((id (focus::create-ticket "Update Test"))
         (updated (focus::update-ticket id :status "closed" :priority "low")))
    (is (not (null updated)))
    (is (string= "closed" (getf updated :status)))
    (is (string= "low" (getf updated :priority)))))

(test delete-ticket-via-model
  (let ((id (focus::create-ticket "Delete Test")))
    (focus::delete-ticket id)
    (is (null (focus::get-ticket-by-id id)))))

(test search-tickets-test
  (let ((id (focus::create-ticket "Searchable Issue" :description "unique-term-xyz")))
    (let ((results (focus::search-tickets "unique-term-xyz")))
      (is (listp results))
      (is (> (length results) 0)))))

(test list-users
  (let ((users (focus::list-users)))
    (is (listp users))))
