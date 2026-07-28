ALTER TABLE ticket_labels DROP CONSTRAINT ticket_labels_ticket_id_fkey;
ALTER TABLE comments DROP CONSTRAINT comments_ticket_id_fkey;
ALTER TABLE activity DROP CONSTRAINT activity_ticket_id_fkey;
ALTER TABLE attachments DROP CONSTRAINT attachments_ticket_id_fkey;

ALTER TABLE tickets RENAME TO issues;

ALTER TABLE comments RENAME COLUMN ticket_id TO issue_id;
ALTER TABLE activity RENAME COLUMN ticket_id TO issue_id;
ALTER TABLE attachments RENAME COLUMN ticket_id TO issue_id;

ALTER TABLE ticket_labels RENAME COLUMN ticket_id TO issue_id;
ALTER TABLE ticket_labels RENAME TO issue_labels;
ALTER INDEX idx_ticket_labels_ticket_id RENAME TO idx_issue_labels_issue_id;
ALTER INDEX idx_ticket_labels_label_id RENAME TO idx_issue_labels_label_id;

ALTER TABLE issue_labels ADD CONSTRAINT issue_labels_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE;
ALTER TABLE issue_labels ADD CONSTRAINT issue_labels_label_id_fkey FOREIGN KEY (label_id) REFERENCES labels(id) ON DELETE CASCADE;
ALTER TABLE comments ADD CONSTRAINT comments_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE;
ALTER TABLE activity ADD CONSTRAINT activity_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE;
ALTER TABLE attachments ADD CONSTRAINT attachments_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE;
