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

;;; Embedded static assets — served from the binary image, no filesystem needed.

(defvar *static-assets-cache* (make-hash-table :test #'equal)
  "Cache of decoded static assets keyed by relative path.")

(defun static-asset-bytes (rel-path)
  "Return the octet vector for REL-PATH embedded in the image, or NIL."
  (or (gethash rel-path *static-assets-cache*)
      (let ((entry (find rel-path *static-assets* :test #'string= :key #'car)))
        (when entry
          (let ((bytes (cl-base64:base64-string-to-usb8-array (cdr entry))))
            (setf (gethash rel-path *static-assets-cache*) bytes)
            bytes)))))

(defun static-asset-paths ()
  "List all embedded static asset paths."
  (iter (for entry in *static-assets*)
        (collect (car entry))))

(defun list-static-files (dir)
  "Recursively list files under DIR."
  (let ((result '()))
    (labels ((walk (d)
               (iter (for entry in (uiop:directory-files d))
                     (push entry result))
               (iter (for sub in (uiop:subdirectories d))
                     (walk sub))))
      (walk (uiop:ensure-directory-pathname dir)))
    (sort result #'string< :key #'file-namestring)))

(defun read-static-file (file)
  "Read a file as an octet vector."
  (with-open-file (s file :direction :input :element-type '(unsigned-byte 8))
    (let ((data (make-array (file-length s) :element-type '(unsigned-byte 8))))
      (read-sequence data s)
      data)))

(defun reload-static-assets (&optional (dir "frontend/resources/public/"))
  "Hot-reload static assets from DIR into the running image.
  Re-encodes every file and swaps the embedded table, so no server
  rebuild is needed. Returns the number of assets loaded."
  (let* ((root (uiop:ensure-absolute-pathname
                (uiop:ensure-directory-pathname dir)
                (uiop:getcwd)))
         (new-assets
           (iter (for file in (list-static-files root))
                 (collect (cons (namestring (uiop:enough-pathname file root))
                                (cl-base64:usb8-array-to-base64-string
                                 (read-static-file file)
                                 :columns 0))))))
    (setf *static-assets* new-assets)
    (clrhash *static-assets-cache*)
    (length new-assets)))