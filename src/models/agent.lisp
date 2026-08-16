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

;;; Agent model — non-human identities owned by users, used via API keys.

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
  "Delete an agent. Cascades to keys."
  (db-execute "DELETE FROM agents WHERE id = $1" id))

;;; Agent API keys

(defun random-token-hex (&optional (bytes 24))
  "Return BYTES cryptographically-random bytes as a hex string."
  (let ((buf (ironclad:random-data bytes)))
    (ironclad:byte-array-to-hex-string buf)))

(defun hash-agent-key (key)
  "Return the SHA-256 hex digest of KEY."
  (let ((sha (ironclad:sha256 (ironclad:ascii-string-to-byte-array key))))
    (ironclad:byte-array-to-hex-string sha)))

(defun create-agent-key (agent-id token)
  "Store a hashed agent key. Returns the key row ID."
  (db-query
   "INSERT INTO agent_keys (agent_id, token_hash) VALUES ($1, $2) RETURNING id"
   agent-id (hash-agent-key token)
   :single))

(defun get-agent-key-token-hash (agent-id token)
  "Check if TOKEN is a valid, non-revoked key for AGENT-ID.
   Returns the key row plist or nil, and touches last_used_at."
  (let ((hash (hash-agent-key token))
        (results (pg-query-params
                  "SELECT id, agent_id, token_hash, created_at, last_used_at, revoked
                   FROM agent_keys WHERE agent_id = $1 AND token_hash = $2 AND NOT revoked"
                  (list agent-id hash))))
    (when results
      (db-execute "UPDATE agent_keys SET last_used_at = NOW() WHERE id = $1"
                  (getf (car results) :id))
      (car results))))

(defun find-agent-by-key (token)
  "Resolve TOKEN to an agent. Returns agent plist or nil."
  (let ((hash (hash-agent-key token))
        (results (pg-query-params
                  "SELECT a.id, a.owner_id, a.name, a.description, a.created_at
                   FROM agents a
                   JOIN agent_keys k ON k.agent_id = a.id
                   WHERE k.token_hash = $1 AND NOT k.revoked"
                  (list hash))))
    (when results
      (db-execute "UPDATE agent_keys SET last_used_at = NOW()
                   WHERE token_hash = $1 AND NOT revoked" hash)
      (car results))))

(defun revoke-agent-key (agent-id key-id)
  "Revoke a key for an agent."
  (db-execute "UPDATE agent_keys SET revoked = true WHERE id = $1 AND agent_id = $2"
              key-id agent-id))

(defun list-agent-keys (agent-id)
  "List keys for an agent (without hashes)."
  (pg-query-params
   "SELECT id, agent_id, created_at, last_used_at, revoked
    FROM agent_keys WHERE agent_id = $1 ORDER BY created_at DESC"
   (list agent-id)))