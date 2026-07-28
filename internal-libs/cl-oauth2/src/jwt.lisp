(in-package :cl-oauth2)

;;; JWT decoding (minimal — decode without signature verification)
;;;
;;; For production use with untrusted providers, verify signatures.
;;; For internal Mattermost, decoding is sufficient if the server is trusted.

(defun base64-url-decode (string)
  "Decode a base64url-encoded string."
  (let ((padded (concatenate 'string
                             string
                             (make-string (- 4 (mod (length string) 4))
                                         :initial-element #\=))))
    (cl-base64:base64-string-to-string
     (substitute #\+ #\- (substitute #\_ #\/ padded))
     :flexi-streams)))

(defun decode-jwt-payload (jwt-string)
  "Decode the payload of a JWT without verifying the signature.
Returns an alist of claims."
  (let* ((parts (split-sequence:split-sequence #\. jwt-string))
         (payload-part (second parts)))
    (when payload-part
      (let ((json (base64-url-decode payload-part)))
        (cl-json:decode-json-from-string json)))))

(defun jwt-claim (claim payload-alist)
  "Extract a specific claim from a decoded JWT payload."
  (cdr (assoc claim payload-alist :test #'equal)))

(defun jwt-sub (payload-alist)
  "Get the 'sub' (subject) claim."
  (jwt-claim :sub payload-alist))

(defun jwt-email (payload-alist)
  "Get the 'email' claim."
  (jwt-claim :email payload-alist))

(defun jwt-name (payload-alist)
  "Get the 'name' claim."
  (jwt-claim :name payload-alist))

(defun jwt-username (payload-alist)
  "Get the 'preferred_username' claim."
  (jwt-claim :preferred--username payload-alist))
