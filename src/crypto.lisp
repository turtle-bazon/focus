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

;;; Agent envelope cryptography (ironclad v0.61): static X25519 ECDH pins a
;;; shared secret between the server and one agent shape; the request/response
;;; payload rides in an AES-256-GCM envelope keyed from that secret.
;;;
;;; The agent holds its own X25519 keypair; the server holds one per shape.
;;; Both sides compute the same shared secret: server = DH(server_private,
;;; agent_public), agent = DH(agent_private, server_public).
;;;
;;; Per message, HMAC-SHA256 derives a fresh session key from the master key,
;;; the traffic direction, the timestamp and the random nonce, so a nonce is
;;; never reused under one key. The timestamp is bound into the AAD, giving
;;; replay protection within a freshness window.

(defconstant +envelope-nonce-bytes+ 12)
;; String "constants" are defparameters: fresh string literals are not EQL
;; across loads, which would trip SBCL's DEFCONSTANT-UNEQL check.
(defparameter +envelope-master-label+ "focus-agent-v1")
(defparameter +envelope-aad-prefix+ "focus-envelope-v1")
(defparameter +envelope-direction-request+ "request")
(defparameter +envelope-direction-response+ "response")
(defconstant +envelope-default-window-seconds+ 15)

;;; X25519 key export/import (portable raw 32-byte components, base64-wrapped)

(defun x25519-generate-keypair ()
  "Generate a fresh X25519 keypair. Returns (values private public)."
  (ironclad:generate-key-pair :curve25519))

(defun x25519-export-public (key)
  "Serialize an X25519 public key to a base64 string."
  (cl-base64:usb8-array-to-base64-string
   (getf (ironclad:destructure-public-key key) :y)))

(defun x25519-export-private (key)
  "Serialize an X25519 private key to a base64 string."
  (cl-base64:usb8-array-to-base64-string
   (getf (ironclad:destructure-private-key key) :x)))

(defun x25519-import-public (text)
  "Deserialize an X25519 public key exported by X25519-EXPORT-PUBLIC."
  (ironclad:make-public-key :curve25519
                            :y (cl-base64:base64-string-to-usb8-array text)))

(defun x25519-import-private (text)
  "Deserialize an X25519 private key exported by X25519-EXPORT-PRIVATE.
   The public component is recomputed on import."
  (ironclad:make-private-key :curve25519
                             :x (cl-base64:base64-string-to-usb8-array text)))

(defun x25519-shared-secret (private-key public-key)
  "Compute the 32-byte X25519 shared secret for PRIVATE-KEY and PUBLIC-KEY."
  (ironclad:diffie-hellman private-key public-key))

;;; Envelope key derivation

(defun envelope-master-key (shared-secret)
  "Derive the per-shape master key: HMAC-SHA256(SHARED-SECRET, label)."
  (ironclad:hmac-digest
   (let ((hmac (ironclad:make-hmac shared-secret :sha256)))
     (ironclad:update-hmac hmac
                           (ironclad:ascii-string-to-byte-array
                            +envelope-master-label+))
     hmac)))

(defun envelope-session-key (master-key direction ts nonce)
  "Derive a per-message AES key from MASTER-KEY, DIRECTION, timestamp TS and
   NONCE, so a nonce is never reused under one key."
  (ironclad:hmac-digest
   (let ((hmac (ironclad:make-hmac master-key :sha256)))
     (ironclad:update-hmac hmac
                           (ironclad:ascii-string-to-byte-array
                            (format nil "~a:~d:~a" direction ts
                                    (ironclad:byte-array-to-hex-string nonce))))
     hmac)))

(defun envelope-aad (direction ts)
  "The associated data bound to every envelope message."
  (ironclad:ascii-string-to-byte-array
   (format nil "~a:~a:~d" +envelope-aad-prefix+ direction ts)))

;;; AES-GCM envelope encrypt/decrypt

(defun envelope-encrypt (master-key direction ts plaintext-bytes)
  "Encrypt PLAINTEXT-BYTES into an AES-GCM envelope under MASTER-KEY.
   Returns (values nonce ciphertext tag)."
  (let* ((nonce (ironclad:random-data +envelope-nonce-bytes+))
         (key (envelope-session-key master-key direction ts nonce))
         (enc (ironclad:make-authenticated-encryption-mode
               :gcm :cipher-name :aes :key key
               :initialization-vector nonce))
         (ciphertext (ironclad:encrypt-message enc plaintext-bytes
                                               :associated-data
                                               (envelope-aad direction ts)))
         (tag (ironclad:produce-tag enc)))
    (values nonce ciphertext tag)))

(defun envelope-decrypt (master-key direction ts nonce ciphertext tag)
  "Decrypt an envelope under MASTER-KEY. Returns the plaintext bytes, or
   signals bad-authentication-tag on a tampered or foreign message."
  (let* ((key (envelope-session-key master-key direction ts nonce))
         (dec (ironclad:make-authenticated-encryption-mode
               :gcm :cipher-name :aes :key key
               :initialization-vector nonce :tag tag)))
    (ironclad:decrypt-message dec ciphertext
                              :associated-data (envelope-aad direction ts))))

;;; Envelope wire format: {"v":1,"ts":.,"n":..,"ct":..,"tg":..} (base64 payloads)

(defun envelope-encode-json (ts nonce ciphertext tag)
  "Encode envelope fields into a JSON string with base64 payloads."
  (with-output-to-string (stream)
    (cl-json:encode-json-alist
     `((:v . 1)
       (:ts . ,ts)
       (:n . ,(cl-base64:usb8-array-to-base64-string nonce))
       (:ct . ,(cl-base64:usb8-array-to-base64-string ciphertext))
       (:tg . ,(cl-base64:usb8-array-to-base64-string tag)))
     stream)))

(defun envelope-json-key (alist name)
  "Look up NAME in a cl-json decoded envelope alist (uppercase keywords)."
  (cdr (assoc (intern (string-upcase name) :keyword) alist :test #'equal)))

(defun envelope-parse-json (json-string)
  "Decode envelope JSON into (values ts nonce ciphertext tag), or NIL if any
   field is missing or malformed."
  (let* ((alist (cl-json:decode-json-from-string json-string))
         (ts (envelope-json-key alist "ts"))
         (b64 (lambda (name) (when (envelope-json-key alist name)
                               (cl-base64:base64-string-to-usb8-array
                                (envelope-json-key alist name))))))
    (when (and (integerp ts)
               (> (length (or (envelope-json-key alist "n") "")) 0)
               (> (length (or (envelope-json-key alist "ct") "")) 0)
               (> (length (or (envelope-json-key alist "tg") "")) 0))
      (values ts (funcall b64 "n") (funcall b64 "ct") (funcall b64 "tg")))))

;;; Replay window (both peers use CL's get-universal-time, seconds)

(defun envelope-time-fresh-p (ts &optional (window +envelope-default-window-seconds+))
  "Return T if TS is within WINDOW seconds of now (replay protection)."
  (and (integerp ts)
       (<= (abs (- (get-universal-time) ts)) window)))