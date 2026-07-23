-- v1-baseline
-- The full Marquee project schema as a single baseline.
--
-- Collapsed from the former v1..v14 append-only history (2026-07-23): nothing
-- consumes these databases with a shipped MVP client yet, so the migration
-- trail was flattened into one baseline. Until an MVP client exists this file
-- may be edited in place; once one ships, return to append-only (add v2-… etc.)
-- rather than editing the baseline, so deployed databases can still migrate.

CREATE TABLE project (
  id                        INTEGER PRIMARY KEY AUTOINCREMENT,
  cloud_uid                 TEXT    NOT NULL,
  name                      TEXT    NOT NULL,
  created                   INTEGER NOT NULL,
  updated                   INTEGER NOT NULL,
  retain_originals          INTEGER NOT NULL DEFAULT 1,
  timezone                  TEXT,
  project_code              TEXT,
  show_wallpaper_item_id    INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,
  desktop_wallpaper_item_id INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,
  edit_code_required        INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE media_file (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  source_file_name    TEXT    NOT NULL UNIQUE,
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
  updated             INTEGER NOT NULL,
  optimized_file_name TEXT
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

CREATE UNIQUE INDEX idx_media_file_optimized ON media_file (optimized_file_name);

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
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  playlist_id          INTEGER NOT NULL REFERENCES playlist(id)   ON DELETE CASCADE,
  media_item_id        INTEGER NOT NULL REFERENCES media_item(id) ON DELETE RESTRICT,
  position             INTEGER NOT NULL,
  created              INTEGER NOT NULL,
  updated              INTEGER NOT NULL,
  resource_type        TEXT    NOT NULL DEFAULT 'media_item',
  start_time_portrait  REAL,
  end_time_portrait    REAL,
  start_time_landscape REAL,
  end_time_landscape   REAL
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

CREATE TABLE screen_config (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  name               TEXT    NOT NULL,
  revision           INTEGER NOT NULL DEFAULT 0,   -- monotonic; bumped on any schedule change
  archived           INTEGER NOT NULL DEFAULT 0,
  created            INTEGER NOT NULL,
  updated            INTEGER NOT NULL,
  screen_id          TEXT,
  published_revision INTEGER,
  published_at       INTEGER
);

CREATE TABLE screen_location (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  config_id            INTEGER NOT NULL REFERENCES screen_config(id) ON DELETE CASCADE,
  location_id          TEXT    NOT NULL UNIQUE,   -- globally unique real-world id
  orientation          TEXT    NOT NULL,          -- 'portrait' | 'landscape' (the mount)
  label                TEXT,
  last_checked_at      INTEGER,                   -- unix ms; "is it online?"
  last_pulled_revision INTEGER,                   -- vs config.revision; "needs update?"
  created              INTEGER NOT NULL,
  updated              INTEGER NOT NULL
);

CREATE INDEX idx_screen_code_config ON screen_location (config_id);

CREATE TABLE screen_schedule_entry (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  config_id          INTEGER NOT NULL REFERENCES screen_config(id) ON DELETE CASCADE,
  slot               TEXT    NOT NULL,            -- 'portrait' | 'landscape' | 'demo_station'
  timestamp          INTEGER NOT NULL,            -- most-recent <= now wins, per slot
  playlist_id        INTEGER REFERENCES playlist(id)   ON DELETE RESTRICT,  -- portrait/landscape payload
  background_item_id INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (behind)
  overlay_item_id    INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (front)
  created            INTEGER NOT NULL,
  updated            INTEGER NOT NULL,
  -- Playlist slots carry only a playlist; demo slots carry only branding,
  -- and an overlay requires a background (background is required when branded;
  -- both NULL = blank = exit demo mode).
  CHECK (
    ( slot IN ('portrait','landscape')
        AND background_item_id IS NULL AND overlay_item_id IS NULL )
    OR
    ( slot = 'demo_station'
        AND playlist_id IS NULL
        AND ( background_item_id IS NOT NULL OR overlay_item_id IS NULL ) )
  )
);

CREATE INDEX idx_screen_sched_slot ON screen_schedule_entry (config_id, slot, timestamp);

CREATE TABLE project_days (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  day        TEXT    NOT NULL UNIQUE,
  start_time INTEGER NOT NULL,
  end_time   INTEGER NOT NULL,
  created    INTEGER NOT NULL,
  updated    INTEGER NOT NULL
);

CREATE INDEX idx_project_day_start ON project_days (start_time);
