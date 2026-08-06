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
