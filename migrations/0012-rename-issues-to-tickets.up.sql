-- Drop foreign keys first, rename, then recreate
ALTER TABLE issue_labels DROP CONSTRAINT issue_labels_issue_id_fkey;
ALTER TABLE comments DROP CONSTRAINT comments_issue_id_fkey;
ALTER TABLE activity DROP CONSTRAINT activity_issue_id_fkey;
ALTER TABLE attachments DROP CONSTRAINT attachments_issue_id_fkey;

ALTER TABLE issue_labels RENAME TO ticket_labels;
ALTER TABLE ticket_labels RENAME COLUMN issue_id TO ticket_id;
ALTER INDEX idx_issue_labels_issue_id RENAME TO idx_ticket_labels_ticket_id;
ALTER INDEX idx_issue_labels_label_id RENAME TO idx_ticket_labels_label_id;

ALTER TABLE comments RENAME COLUMN issue_id TO ticket_id;
ALTER TABLE activity RENAME COLUMN issue_id TO ticket_id;
ALTER TABLE attachments RENAME COLUMN issue_id TO ticket_id;

ALTER TABLE issues RENAME TO tickets;

ALTER TABLE ticket_labels ADD CONSTRAINT ticket_labels_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES tickets(id) ON DELETE CASCADE;
ALTER TABLE ticket_labels ADD CONSTRAINT ticket_labels_label_id_fkey FOREIGN KEY (label_id) REFERENCES labels(id) ON DELETE CASCADE;
ALTER TABLE comments ADD CONSTRAINT comments_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES tickets(id) ON DELETE CASCADE;
ALTER TABLE activity ADD CONSTRAINT activity_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES tickets(id) ON DELETE CASCADE;
ALTER TABLE attachments ADD CONSTRAINT attachments_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES tickets(id) ON DELETE CASCADE;
