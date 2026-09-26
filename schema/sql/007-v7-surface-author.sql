-- v7-surface-author
-- Studio Surface Author M1 (PRD 06 §6.1; Platform Reference v25.0.1 §2.4, §6.8,
-- §8, STD-03, STD-04). Three changes, one migration, because they are one
-- decision: the authoring schema speaks the wire format's vocabulary.
--
-- 1. Screen → Surface. "Screen" is retired everywhere — documents, UI, code
--    types and the wire format — so that Studio and Surface are the two
--    distinctions. The three tables and the `screen_id` column take their
--    canonical names: the parent by ALTER TABLE … RENAME, the two child tables
--    by a rebuild (see below), with their indexes recreated under surface
--    names. Same columns, same order, same ids. The slot value `demo_station`
--    is unchanged: it names a mode, not a device.
--
-- 2. project.backing_item_id — the project-level default backing, a media
--    item (still or video) drawn behind transparent content and session
--    boards. A session set's own backing_item_id overrides it for boards.
--    RESTRICT, like the wallpapers: the item cannot be deleted while it is the
--    default. Surface cartridges carry it and keep the pointer; project.db
--    forces it NULL (Cartridge Spec §3.1 — the backing rides with the content).
--
-- 3. Dropped: playlist.backing_item_id, playlist.overlay_item_id,
--    media_item.backing_item_id, media_item.overlay_item_id — the per-slot
--    composition chain, replaced by the project default (STD-03) — and
--    playlist.shuffle, which the Studio Player treats as transport state that
--    is never stored with the show (STD-04). Nothing published these: the
--    cartridge closure no longer expands item → item, and the delete guards
--    that named them go with them.
--
-- KEPT, deliberately: playlist_entry.loop_clip / pause_on_entry /
-- pause_on_completion / disabled and playlist.is_seamless_video. They are
-- the Studio Player's (Reference §8), preserved untouched and never published.
--
-- ⚠️ NOT additive. Renames and dropped columns need both peers on this
-- migration before a show is opened for writing — a v6 peer would not find
-- `screen_config` and would refuse (Architecture §2.3 R6). Both Studios take
-- v7 in one release, and a v6 build opens a v7 show read-only through the
-- supersession guard. Cartridges published from a v7 show carry `surface_*`
-- tables, which a pre-v25 Surface cannot open: that is the intended v25
-- break (the Surface reads through the engine's Loader from there).
--
-- Requires SQLite ≥ 3.35 (DROP COLUMN). GRDB uses the system library
-- (macOS 15 ships 3.43, iOS 16 3.39); sql.js 1.14 carries 3.49.

-- 1. Screen → Surface
--
-- The two child tables are REBUILT rather than renamed. ALTER TABLE … RENAME TO
-- rewrites the REFERENCES clauses of other tables only when legacy_alter_table
-- is OFF; Apple's system SQLite (the one GRDB links) defaults it ON, so with
-- foreign keys off — how both migrators run — a renamed surface_location kept
-- "REFERENCES screen_config(id)" and every later insert would have failed with
-- "no such table" (measured 2026-09-26, sqlite3 3.54.0 aapl). A rebuild carries
-- the rows and their ids across with the references spelled out, on every engine.
ALTER TABLE screen_config RENAME TO surface_config;
ALTER TABLE surface_config RENAME COLUMN screen_id TO surface_id;

CREATE TABLE surface_location (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  config_id            INTEGER NOT NULL REFERENCES surface_config(id) ON DELETE CASCADE,
  location_id          TEXT    NOT NULL UNIQUE,   -- globally unique real-world id
  orientation          TEXT    NOT NULL,          -- 'portrait' | 'landscape' (the mount)
  label                TEXT,
  last_checked_at      INTEGER,                   -- unix ms; "is it online?"
  last_pulled_revision INTEGER,                   -- vs config.revision; "needs update?"
  created              INTEGER NOT NULL,
  updated              INTEGER NOT NULL
);
INSERT INTO surface_location
  (id, config_id, location_id, orientation, label, last_checked_at, last_pulled_revision, created, updated)
  SELECT id, config_id, location_id, orientation, label, last_checked_at, last_pulled_revision, created, updated
  FROM screen_location ORDER BY id;
DROP TABLE screen_location;
CREATE INDEX idx_surface_location_config ON surface_location (config_id);

CREATE TABLE surface_schedule_entry (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  config_id          INTEGER NOT NULL REFERENCES surface_config(id) ON DELETE CASCADE,
  slot               TEXT    NOT NULL,            -- 'portrait' | 'landscape' | 'demo_station'
  timestamp          INTEGER NOT NULL,            -- most-recent <= now wins, per slot
  playlist_id        INTEGER REFERENCES playlist(id)   ON DELETE RESTRICT,  -- portrait/landscape payload
  background_item_id INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (behind)
  overlay_item_id    INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (front)
  created            INTEGER NOT NULL,
  updated            INTEGER NOT NULL,
  -- Playlist slots carry only a playlist. Demo slots carry branding and MAY
  -- carry a playlist (PIP content, rendered by the consumer at the opposite
  -- orientation); an overlay still requires a background, and all-NULL =
  -- blank = exit demo mode. Verbatim from the baseline.
  CHECK (
    ( slot IN ('portrait','landscape')
        AND background_item_id IS NULL AND overlay_item_id IS NULL )
    OR
    ( slot = 'demo_station'
        AND ( background_item_id IS NOT NULL OR overlay_item_id IS NULL ) )
  )
);
INSERT INTO surface_schedule_entry
  (id, config_id, slot, timestamp, playlist_id, background_item_id, overlay_item_id, created, updated)
  SELECT id, config_id, slot, timestamp, playlist_id, background_item_id, overlay_item_id, created, updated
  FROM screen_schedule_entry ORDER BY id;
DROP TABLE screen_schedule_entry;
CREATE INDEX idx_surface_sched_slot ON surface_schedule_entry (config_id, slot, timestamp);

-- 2. The project default backing
ALTER TABLE project ADD COLUMN backing_item_id INTEGER REFERENCES media_item(id) ON DELETE RESTRICT;

-- 3. The per-slot composition chain, and shuffle
ALTER TABLE playlist   DROP COLUMN backing_item_id;
ALTER TABLE playlist   DROP COLUMN overlay_item_id;
ALTER TABLE playlist   DROP COLUMN shuffle;
ALTER TABLE media_item DROP COLUMN backing_item_id;
ALTER TABLE media_item DROP COLUMN overlay_item_id;
