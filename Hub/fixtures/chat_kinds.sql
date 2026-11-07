-- One chat of each kind the hub opens in Messages to mark it read (HubCoreTests/OpenURLTests).
-- Only the chat table's columns the hub reads. Every number, address and ID here is invented.
CREATE TABLE chat (guid TEXT, style INT, service_name TEXT, chat_identifier TEXT, display_name TEXT, group_id TEXT);
CREATE TABLE handle (id TEXT);
CREATE TABLE message (guid TEXT, text TEXT, attributedBody BLOB, date INT, is_from_me INT, is_read INT, handle_id INT,
    balloon_bundle_id TEXT, payload_data BLOB, item_type INT DEFAULT 0, associated_message_guid TEXT,
    associated_message_type INT DEFAULT 0);
CREATE TABLE chat_message_join (chat_id INT, message_id INT, message_date INT);
CREATE TABLE chat_handle_join (chat_id INT, handle_id INT);

-- style 45 is a chat with one person, 43 a group. From macOS 26 every GUID starts with "any;".
INSERT INTO chat VALUES
  ('iMessage;-;+15555550101', 45, 'iMessage', '+15555550101', '', '7C1D2E3F-0000-4000-8000-000000000101'),
  ('any;-;fixture.friend@example.com', 45, 'iMessage', 'fixture.friend@example.com', '', '7C1D2E3F-0000-4000-8000-000000000102'),
  ('SMS;-;+15555550103', 45, 'SMS', '+15555550103', '', '7C1D2E3F-0000-4000-8000-000000000103'),
  ('any;-;+15555550104', 45, 'RCS', '+15555550104', '', '7C1D2E3F-0000-4000-8000-000000000104'),
  ('SMS;-;+15555550105', 45, 'SMS', '+15555550105', '', NULL),
  ('iMessage;+;chat100000000000000001', 43, 'iMessage', 'chat100000000000000001', 'Family', '7C1D2E3F-0000-4000-8000-000000000106'),
  ('any;+;chat100000000000000002', 43, 'iMessage', 'chat100000000000000002', '', '');
