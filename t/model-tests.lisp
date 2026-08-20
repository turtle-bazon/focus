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

(test envelope-roundtrip-and-tamper
  "X25519 ECDH + AES-GCM envelope: both sides derive the same master key,
   plaintext survives a round trip, and tampering is detected."
  (multiple-value-bind (server-private server-public)
      (focus::x25519-generate-keypair)
    (multiple-value-bind (agent-private agent-public)
        (focus::x25519-generate-keypair)
      ;; Simulate persisted base64 halves, as stored in the DB and ~/.focus-cli.
      (let* ((master-server
              (focus::envelope-master-key
               (focus::x25519-shared-secret
                (focus::x25519-import-private
                 (focus::x25519-export-private server-private))
                (focus::x25519-import-public
                 (focus::x25519-export-public agent-public)))))
             (master-agent
              (focus::cli-master-key
               :server-public (focus::x25519-export-public server-public)
               :agent-private (focus::x25519-export-private agent-private)))
             (ts (get-universal-time))
             (plaintext (flexi-streams:string-to-octets
                         "{\"method\":\"get\",\"path\":\"/api/boards\"}")))
        (is (equalp master-server master-agent))
        (multiple-value-bind (nonce ciphertext tag)
            (focus::envelope-encrypt master-agent
                                     focus::+envelope-direction-request+
                                     ts plaintext)
          (let ((json (focus::envelope-encode-json ts nonce ciphertext tag)))
            (multiple-value-bind (ts2 nonce2 ciphertext2 tag2)
                (focus::envelope-parse-json json)
              (is (= ts ts2))
              (is (equalp nonce nonce2))
              (is (string=
                   "{\"method\":\"get\",\"path\":\"/api/boards\"}"
                   (flexi-streams:octets-to-string
                    (focus::envelope-decrypt
                     master-server focus::+envelope-direction-request+
                     ts2 nonce2 ciphertext2 tag2))))
              ;; A flipped ciphertext bit must fail tag verification.
              (setf (aref ciphertext2 0) (logxor (aref ciphertext2 0) 1))
              (signals ironclad:bad-authentication-tag
                (focus::envelope-decrypt
                 master-server focus::+envelope-direction-request+
                 ts2 nonce2 ciphertext2 tag2)))))))))

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
