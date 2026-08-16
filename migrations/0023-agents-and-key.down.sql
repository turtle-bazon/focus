ALTER TABLE comments DROP COLUMN IF EXISTS agent_id;
ALTER TABLE activity DROP COLUMN IF EXISTS agent_id;

ALTER TABLE ticket_observers DROP CONSTRAINT IF EXISTS ticket_observers_observer_type_check;
ALTER TABLE ticket_observers ADD CONSTRAINT ticket_observers_observer_type_check
  CHECK (observer_type IN ('user', 'group'));

ALTER TABLE board_members DROP CONSTRAINT IF EXISTS board_members_member_type_check;
ALTER TABLE board_members ADD CONSTRAINT board_members_member_type_check
  CHECK (member_type IN ('user', 'group'));

DROP TABLE IF EXISTS agent_keys;
DROP TABLE IF EXISTS agents;