DROP TABLE media_item_tag;

CREATE TABLE tag (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  name    TEXT    NOT NULL,
  color   TEXT,
  created INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_tag_name ON tag (name COLLATE NOCASE);

CREATE TABLE tag_assignment (
  tag_id      INTEGER NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
  entity_type TEXT    NOT NULL,
  entity_id   INTEGER NOT NULL,
  PRIMARY KEY (tag_id, entity_type, entity_id)
);
CREATE INDEX idx_tag_assignment_entity ON tag_assignment (entity_type, entity_id);
CREATE INDEX idx_tag_assignment_tag    ON tag_assignment (tag_id, entity_type);
