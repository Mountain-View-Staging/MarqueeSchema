CREATE TABLE project (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  cloud_uid TEXT    NOT NULL,
  name      TEXT    NOT NULL,
  created   INTEGER NOT NULL,
  updated   INTEGER NOT NULL
);

CREATE TABLE media_file (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  file_name           TEXT    NOT NULL UNIQUE,
  thumbnail_file_name TEXT,
  content_type        TEXT    NOT NULL,
  width               INTEGER,
  height              INTEGER,
  orientation         TEXT,
  aspect_ratio        REAL,
  intrinsic_duration  REAL,
  file_size           INTEGER,
  source_hash         TEXT,
  content_hash        TEXT,
  codec               TEXT,
  color_space         TEXT,
  was_converted       INTEGER NOT NULL DEFAULT 0,
  original_type       TEXT,
  original_file_name  TEXT,
  source_document     TEXT,
  source              TEXT,
  created             INTEGER NOT NULL,
  updated             INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_media_file_source_hash ON media_file (source_hash);
CREATE INDEX idx_media_file_orientation ON media_file (orientation);

CREATE TABLE media_item (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  name              TEXT    NOT NULL,
  portrait_file_id  INTEGER REFERENCES media_file(id) ON DELETE RESTRICT,
  landscape_file_id INTEGER REFERENCES media_file(id) ON DELETE RESTRICT,
  display_duration  REAL,
  system_generated  INTEGER NOT NULL DEFAULT 0,
  audio_priority    TEXT,
  backing_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,
  overlay_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,
  archived          INTEGER NOT NULL DEFAULT 0,
  created           INTEGER NOT NULL,
  updated           INTEGER NOT NULL,
  CHECK (portrait_file_id IS NOT NULL OR landscape_file_id IS NOT NULL)
);

CREATE TABLE media_item_tag (
  item_id INTEGER NOT NULL REFERENCES media_item(id) ON DELETE CASCADE,
  tag     TEXT    NOT NULL,
  PRIMARY KEY (item_id, tag)
);
