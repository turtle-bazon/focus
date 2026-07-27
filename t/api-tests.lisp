(in-package :focus/tests)

(in-suite focus-tests)

(test create-issue-via-model
  (let ((id (focus::create-issue "API Test" :description "Testing" :priority "high")))
    (is (numberp id))
    (let ((issue (focus::get-issue-by-id id)))
      (is (string= "API Test" (getf issue :title))))))

(test update-issue-via-model
  (let* ((id (focus::create-issue "Update Test"))
         (updated (focus::update-issue id :status "closed" :priority "low")))
    (is (not (null updated)))
    (is (string= "closed" (getf updated :status)))
    (is (string= "low" (getf updated :priority)))))

(test delete-issue-via-model
  (let ((id (focus::create-issue "Delete Test")))
    (focus::delete-issue id)
    (is (null (focus::get-issue-by-id id)))))

(test search-issues-test
  (let ((id (focus::create-issue "Searchable Issue" :description "unique-term-xyz")))
    (let ((results (focus::search-issues "unique-term-xyz")))
      (is (listp results))
      (is (> (length results) 0)))))

(test list-users
  (let ((users (focus::list-users)))
    (is (listp users))))
