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

;;; Agent model — non-human identities owned by users, accessed remotely via
;;; X25519 key shapes (see src/crypto.lisp).

(defun create-agent (owner-id name &key description)
  "Create an agent owned by OWNER-ID. Returns the agent ID."
  (db-query
   "INSERT INTO agents (owner_id, name, description) VALUES ($1, $2, $3) RETURNING id"
   owner-id name description
   :single))

(defun get-agent-by-id (id)
  "Get an agent by ID. Returns plist or nil."
  (let ((results (db-query
                  "SELECT id, owner_id, name, description, created_at
                   FROM agents WHERE id = $1"
                  id :alists)))
    (when results (alist-to-plist (car results)))))

(defun list-agents (&key owner-id)
  "List agents, optionally filtered by owner."
  (if owner-id
      (pg-query-params
       "SELECT id, owner_id, name, description, created_at
        FROM agents WHERE owner_id = $1 ORDER BY name"
       (list owner-id))
      (pg-query-params
       "SELECT id, owner_id, name, description, created_at
        FROM agents ORDER BY owner_id, name"
       nil)))

(defun update-agent (id &key name description)
  "Update agent fields."
  (let ((sets '())
        (params '())
        (i 0))
    (when name
      (incf i)
      (push (format nil "name = $~d" i) sets)
      (push name params))
    (when description
      (incf i)
      (push (format nil "description = $~d" i) sets)
      (push description params))
    (when sets
      (incf i)
      (push id params)
      (pg-query-params
       (format nil "UPDATE agents SET ~{~a~^, ~} WHERE id = $~d"
               (reverse sets) i)
       (reverse params))))
  (get-agent-by-id id))

(defun delete-agent (id)
  "Delete an agent. Cascades to shapes."
  (db-execute "DELETE FROM agents WHERE id = $1" id))

;;; Agent API key helpers (still used for bearer hashing and display)

(defun random-token-hex (&optional (bytes 24))
  "Return BYTES cryptographically-random bytes as a hex string."
  (let ((buf (ironclad:random-data bytes)))
    (ironclad:byte-array-to-hex-string buf)))

(defun hash-agent-key (key)
  "Return the SHA-256 hex digest of KEY."
  (let ((sha (ironclad:digest-sequence :sha256
                                       (ironclad:ascii-string-to-byte-array key))))
    (ironclad:byte-array-to-hex-string sha)))

(defun token-prefix (token)
  "Return the first 12 characters of TOKEN for display."
  (subseq token 0 (min 12 (length token))))

;;; Agent key shapes — X25519 credential exchange (see src/crypto.lisp)

(defun create-agent-shape (agent-id name)
  "Create a new credential shape for AGENT-ID: the server keypair is kept in
   the database, the agent keypair's private half is returned to the caller.
   Returns (values shape-id bearer server-public agent-private)."
  (multiple-value-bind (server-private server-public) (x25519-generate-keypair)
    (multiple-value-bind (agent-private agent-public) (x25519-generate-keypair)
      (let* ((bearer (format nil "focus~d-~a" agent-id (random-token-hex)))
             (id (db-query
                  "INSERT INTO agent_key_shapes
                    (agent_id, name, bearer_hash, token_prefix,
                     server_private, agent_public)
                  VALUES ($1, $2, $3, $4, $5, $6) RETURNING id"
                  agent-id name
                  (hash-agent-key bearer)
                  (token-prefix bearer)
                  (x25519-export-private server-private)
                  (x25519-export-public agent-public)
                  :single)))
        (values id bearer
                (x25519-export-public server-public)
                (x25519-export-private agent-private))))))

(defun get-agent-shape-by-bearer (bearer)
  "Resolve BEARER to a non-revoked shape plist, touching last_used_at.
   Returns the shape plist (hyphenated keys) or NIL."
  (let ((results (pg-query-params
                  "SELECT id, agent_id, name, bearer_hash, token_prefix,
                          server_private, agent_public,
                          created_at, last_used_at, revoked
                   FROM agent_key_shapes
                   WHERE bearer_hash = $1 AND NOT revoked"
                  (list (hash-agent-key bearer)))))
    (when results
      (db-execute "UPDATE agent_key_shapes SET last_used_at = NOW() WHERE id = $1"
                  (getf (car results) :id))
      (hyphenate-plist-keys (car results)))))

(defun list-agent-shapes (agent-id)
  "List shapes for an agent (secret material excluded)."
  (pg-query-params
   "SELECT id, agent_id, name, token_prefix, created_at, last_used_at, revoked
    FROM agent_key_shapes WHERE agent_id = $1 ORDER BY created_at DESC"
   (list agent-id)))

(defun revoke-agent-shape (agent-id shape-id)
  "Delete a shape for an agent (revoked shapes are hard-deleted)."
  (db-execute "DELETE FROM agent_key_shapes WHERE id = $1 AND agent_id = $2"
              shape-id agent-id))