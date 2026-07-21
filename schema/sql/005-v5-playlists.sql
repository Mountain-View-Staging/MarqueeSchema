CREATE TABLE playlist (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  name              TEXT    NOT NULL,
  shuffle           INTEGER NOT NULL DEFAULT 0,
  is_seamless_video INTEGER NOT NULL DEFAULT 0,
  backing_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,
  overlay_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,
  archived          INTEGER NOT NULL DEFAULT 0,
  created           INTEGER NOT NULL,
  updated           INTEGER NOT NULL
);

CREATE TABLE playlist_entry (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  playlist_id   INTEGER NOT NULL REFERENCES playlist(id)   ON DELETE CASCADE,
  media_item_id INTEGER NOT NULL REFERENCES media_item(id) ON DELETE RESTRICT,
  position      INTEGER NOT NULL,
  created       INTEGER NOT NULL,
  updated       INTEGER NOT NULL
);
CREATE INDEX idx_playlist_entry_order ON playlist_entry (playlist_id, position);
CREATE INDEX idx_playlist_entry_item  ON playlist_entry (media_item_id);

CREATE TABLE directive (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  entry_id   INTEGER NOT NULL REFERENCES playlist_entry(id) ON DELETE CASCADE,
  type       TEXT    NOT NULL,   -- 'standard' | 'takeover'
  timestamp  INTEGER NOT NULL,
  on_screen  INTEGER NOT NULL,
  timezone   TEXT,
  created    INTEGER NOT NULL,
  updated    INTEGER NOT NULL
);
CREATE INDEX idx_directive_entry ON directive (entry_id, timestamp);
