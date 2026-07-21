// GENERATED FILE — DO NOT EDIT.
// Source: MarqueeSchema/schema/migrations.json (+ schema/sql/*.sql)
// Regenerate: node tools/generate.mjs
// Checksum:   e1b4076b83df649400d407f9e5c0dc4aa31316f8481a60cbe958465dd24e5352

import Foundation
import GRDB

/// The Marquee schema, generated from the shared `MarqueeSchema` repo.
///
/// Do not add migrations here — add them to `schema/migrations.json` in that
/// repo and regenerate, so the Swift and JavaScript peers stay identical. The
/// identifiers below are written verbatim into `grdb_migrations` and compared
/// character-for-character across implementations.
public enum MarqueeSchema {

    /// sha256 over every identifier + SQL body. Compare across peers to detect drift.
    public static let checksum = "e1b4076b83df649400d407f9e5c0dc4aa31316f8481a60cbe958465dd24e5352"

    /// Ordered, append-only.
    public static let knownIdentifiers: [String] = [
        "v1-relational",
        "v2-tags",
        "v3-source-optimized",
        "v4-retain-originals",
        "v5-playlists",
        "v6-project-schedule",
        "v7-entry-resource-type",
        "v8-entry-duration-override",
        "v9-screens",
        "v10-screen-distribution",
        "v11-project-code",
        "v12-project-wallpapers",
        "v13-project-days",
    ]

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // Relational core: project / media_file / media_item / media_item_tag. Replaces the former blob-mirror `records` table.
        migrator.registerMigration("v1-relational") { db in
            try db.execute(sql: #"""
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
"""#)
        }
        // Shared tag vocabulary + polymorphic cross-type assignment. Dissolves MediaSet: grouping = entities carrying a tag.
        migrator.registerMigration("v2-tags") { db in
            try db.execute(sql: #"""
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
"""#)
        }
        // Split storage into write-once original + optional optimized copy. Deliverable = optimized ?? source.
        migrator.registerMigration("v3-source-optimized") { db in
            try db.execute(sql: #"""
ALTER TABLE media_file RENAME COLUMN file_name TO source_file_name;
ALTER TABLE media_file ADD COLUMN optimized_file_name TEXT;
CREATE UNIQUE INDEX idx_media_file_optimized ON media_file (optimized_file_name);
"""#)
        }
        // Per-project default for optimize original-retention (keep vs consume).
        migrator.registerMigration("v4-retain-originals") { db in
            try db.execute(sql: #"""
ALTER TABLE project ADD COLUMN retain_originals INTEGER NOT NULL DEFAULT 1;
"""#)
        }
        // Playlists: ordered MediaItem instances + per-instance directives. The Playlist is the single directive authority.
        migrator.registerMigration("v5-playlists") { db in
            try db.execute(sql: #"""
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
"""#)
        }
        // Project timezone. (The former start_date/end_date range moved to project_days in v13; this migration was trimmed in place.)
        migrator.registerMigration("v6-project-schedule") { db in
            try db.execute(sql: #"""
ALTER TABLE project ADD COLUMN timezone TEXT;
"""#)
        }
        // Forward-declared open-vocabulary discriminator so the entry contract is stable. Today only 'media_item' resolves.
        migrator.registerMigration("v7-entry-resource-type") { db in
            try db.execute(sql: #"""
ALTER TABLE playlist_entry
  ADD COLUMN resource_type TEXT NOT NULL DEFAULT 'media_item';
"""#)
        }
        // Per-instance playback windows in seconds of MEDIA time (clip offsets, not wall-clock), one pair per orientation.
        migrator.registerMigration("v8-entry-duration-override") { db in
            try db.execute(sql: #"""
ALTER TABLE playlist_entry ADD COLUMN start_time_portrait  REAL;
ALTER TABLE playlist_entry ADD COLUMN end_time_portrait    REAL;
ALTER TABLE playlist_entry ADD COLUMN start_time_landscape REAL;
ALTER TABLE playlist_entry ADD COLUMN end_time_landscape   REAL;
"""#)
        }
        // Screens: screen_config (scheduling unit) + screen_code (endpoints) + screen_schedule_entry (most-recent-<=-now-wins per slot).
        migrator.registerMigration("v9-screens") { db in
            try db.execute(sql: #"""
CREATE TABLE screen_config (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  name      TEXT    NOT NULL,
  revision  INTEGER NOT NULL DEFAULT 0,   -- monotonic; bumped on any schedule change
  archived  INTEGER NOT NULL DEFAULT 0,
  created   INTEGER NOT NULL,
  updated   INTEGER NOT NULL
);

CREATE TABLE screen_code (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  config_id            INTEGER NOT NULL REFERENCES screen_config(id) ON DELETE CASCADE,
  code                 TEXT    NOT NULL UNIQUE,   -- globally unique real-world id
  orientation          TEXT    NOT NULL,          -- 'portrait' | 'landscape' (the mount)
  label                TEXT,
  last_checked_at      INTEGER,                   -- unix ms; "is it online?"
  last_pulled_revision INTEGER,                   -- vs config.revision; "needs update?"
  created              INTEGER NOT NULL,
  updated              INTEGER NOT NULL
);
CREATE INDEX idx_screen_code_config ON screen_code (config_id);

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
"""#)
        }
        // Cartridge-as-file identity: user-settable screen_id names the cartridge; screen_code becomes screen_location. Length/format/uniqueness are UI-enforced, not DB hard-stops.
        migrator.registerMigration("v10-screen-distribution") { db in
            try db.execute(sql: #"""
ALTER TABLE screen_config ADD COLUMN screen_id TEXT;

ALTER TABLE screen_config ADD COLUMN published_revision INTEGER;
ALTER TABLE screen_config ADD COLUMN published_at       INTEGER;

ALTER TABLE screen_code RENAME TO screen_location;
ALTER TABLE screen_location RENAME COLUMN code TO location_id;
"""#)
        }
        // ShowCode: short user-settable project addressing code. Consumers self-resolve <projectCode>/<screenCode>.db.
        migrator.registerMigration("v11-project-code") { db in
            try db.execute(sql: #"""
ALTER TABLE project ADD COLUMN project_code TEXT;
"""#)
        }
        // Project-level wallpaper pointers. ADD COLUMN with REFERENCES is legal because the NULL default satisfies SQLite's add-column FK rule.
        migrator.registerMigration("v12-project-wallpapers") { db in
            try db.execute(sql: #"""
ALTER TABLE project ADD COLUMN show_wallpaper_item_id INTEGER
  REFERENCES media_item(id) ON DELETE RESTRICT;

ALTER TABLE project ADD COLUMN desktop_wallpaper_item_id INTEGER
  REFERENCES media_item(id) ON DELETE RESTRICT;
"""#)
        }
        // Explicit non-contiguous schedule days, authored in the project timezone and stored verbatim as unix ms.
        migrator.registerMigration("v13-project-days") { db in
            try db.execute(sql: #"""
CREATE TABLE project_days (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  day        TEXT    NOT NULL UNIQUE,
  start_time INTEGER NOT NULL,
  end_time   INTEGER NOT NULL,
  created    INTEGER NOT NULL,
  updated    INTEGER NOT NULL
);
CREATE INDEX idx_project_day_start ON project_days (start_time);
"""#)
        }
        return migrator
    }
}
