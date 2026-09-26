// GENERATED FILE — DO NOT EDIT.
// Source: MarqueeSchema/schema/migrations.json (+ schema/sql/*.sql)
// Regenerate: node tools/generate.mjs
// Checksum:   73f4cd8e1ee9abe8372f5637445d0abd33171993a209e4adad95b2a93747af95

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
    public static let checksum = "73f4cd8e1ee9abe8372f5637445d0abd33171993a209e4adad95b2a93747af95"

    /// Ordered, append-only.
    public static let knownIdentifiers: [String] = [
        "v1-baseline",
        "v2-media-variants",
        "v3-media-optimization",
        "v4-entry-playback-states",
        "v5-brand-style",
        "v6-brand-member",
        "v7-surface-author",
    ]

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // The full Marquee project schema as a single baseline, flattened from the former v1..v14 append-only history (2026-07-23). Dev-mode edit 2026-08-15: sessions (session/session_set/session_set_entry), playlist_entry resource_type expansion to session sets, demo-slot playlist (SPEC-sqlite-cartridge-deployment).
        migrator.registerMigration("v1-baseline") { db in
            try db.execute(sql: #"""
-- v1-baseline
-- The full Marquee project schema as a single baseline.
--
-- Collapsed from the former v1..v14 append-only history (2026-07-23): nothing
-- consumes these databases with a shipped MVP client yet, so the migration
-- trail was flattened into one baseline. Until an MVP client exists this file
-- may be edited in place; once one ships, return to append-only (add v2-… etc.)
-- rather than editing the baseline, so deployed databases can still migrate.
--
-- Dev-mode edit 2026-08-15 (SPEC-sqlite-cartridge-deployment, legacy Studio
-- convergence): sessions join the schema (session / session_set /
-- session_set_entry), playlist_entry generalizes to non-media resources via the
-- forward-declared resource_type vocabulary, and the demo_station slot may
-- carry a playlist (PIP content) alongside its branding.

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

-- Sessions: conference/agenda content rendered by the player (schedule boards,
-- room signs). Imported from external integrations, so the variable shapes
-- (presenters, attributes incl. multi-room time attributes, the layer-2
-- schedule_template diff) stay JSON-tolerant TEXT rather than fully relational —
-- they are consumed opaquely by the renderer.
CREATE TABLE session (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT    NOT NULL,
  abstract    TEXT,
  presenters  TEXT,             -- JSON array
  attributes  TEXT,             -- JSON array (vendor attributes; legacy producers may include time attributes)
  source_id   TEXT,             -- vendor session id; NULL = manually authored
  source_type TEXT,             -- provider discriminator, e.g. 'rainfocus' | 'spreadsheet'
  source_name TEXT,             -- provider display name at import time
  created     INTEGER NOT NULL,
  updated     INTEGER NOT NULL
);

CREATE INDEX idx_session_source ON session (source_id);

CREATE TABLE session_set (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  name              TEXT    NOT NULL,
  render_modes      TEXT    NOT NULL DEFAULT '["simple"]',   -- JSON array
  duration          REAL    NOT NULL DEFAULT 8,              -- seconds per board page
  backing_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,
  logo_item_id      INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,
  schedule_template TEXT,       -- JSON diff vs the Surface baseline; absent = baseline
  source_id         TEXT,       -- vendor room id; NULL = manually authored set
  source_name       TEXT,       -- vendor room display name at import time
  created           INTEGER NOT NULL,
  updated           INTEGER NOT NULL
);

-- A session's membership in a set, at a specific time window. session_time_id
-- distinguishes multiple time slots of the same session (multi-room);
-- source_room_id records which vendor room minted the slot so a multi-room
-- sync can reconcile per room without pruning its siblings.
CREATE TABLE session_set_entry (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  session_set_id  INTEGER NOT NULL REFERENCES session_set(id) ON DELETE CASCADE,
  session_id      INTEGER NOT NULL REFERENCES session(id)     ON DELETE RESTRICT,
  session_time_id TEXT,
  start_time      INTEGER NOT NULL,
  end_time        INTEGER NOT NULL,
  source_room_id  TEXT,
  room_name       TEXT,
  created         INTEGER NOT NULL,
  updated         INTEGER NOT NULL
);

CREATE INDEX idx_session_set_entry_set ON session_set_entry (session_set_id, start_time);

-- Integration provider configuration (credentials, cached room catalog, sync
-- bookkeeping) as an opaque JSON blob per provider. Authoring-side only: it
-- travels with the project database so the team shares one configuration, and
-- every cartridge kind drops this table before publishing.
CREATE TABLE integration (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  provider TEXT    NOT NULL UNIQUE,
  config   TEXT    NOT NULL DEFAULT '{}',   -- JSON object
  created  INTEGER NOT NULL,
  updated  INTEGER NOT NULL
);

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

-- An entry plays a resource; resource_type is the open-vocabulary discriminator
-- (forward-declared in v7 of the pre-baseline history — "today only 'media_item'
-- resolves"; 'session_set' is its first expansion, 2026-08-15). The implication
-- CHECKs pin integrity for the known types without closing the vocabulary.
CREATE TABLE playlist_entry (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  playlist_id          INTEGER NOT NULL REFERENCES playlist(id) ON DELETE CASCADE,
  media_item_id        INTEGER REFERENCES media_item(id)  ON DELETE RESTRICT,
  session_set_id       INTEGER REFERENCES session_set(id) ON DELETE RESTRICT,
  position             INTEGER NOT NULL,
  created              INTEGER NOT NULL,
  updated              INTEGER NOT NULL,
  resource_type        TEXT    NOT NULL DEFAULT 'media_item',
  start_time_portrait  REAL,
  end_time_portrait    REAL,
  start_time_landscape REAL,
  end_time_landscape   REAL,
  CHECK (resource_type <> 'media_item'  OR media_item_id  IS NOT NULL),
  CHECK (resource_type <> 'session_set' OR session_set_id IS NOT NULL)
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
  -- Playlist slots carry only a playlist. Demo slots carry branding and MAY
  -- carry a playlist (PIP content, rendered by the consumer at the opposite
  -- orientation — 2026-08-15, SPEC-sqlite-cartridge-deployment D3); an overlay
  -- still requires a background, and all-NULL = blank = exit demo mode.
  CHECK (
    ( slot IN ('portrait','landscape')
        AND background_item_id IS NULL AND overlay_item_id IS NULL )
    OR
    ( slot = 'demo_station'
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
"""#)
        }
        // media_file_variant — MediaFile children (optimized/webOptimized/mask/extract/…), authoring db only; cartridge builders drop it and resolve one deliverable into the existing media_file columns, so the cartridge artifact schema is unchanged. First append-only migration since the baseline flatten.
        migrator.registerMigration("v2-media-variants") { db in
            try db.execute(sql: #"""
-- v2-media-variants
-- MediaFile children: alternate representations of the same content —
-- optimized, webOptimized, mask, extract, and future kinds — each a real
-- file on disk, with the parent media_file row aware of them.
--
-- AUTHORING (main db) ONLY. Cartridge builders DROP this table and resolve a
-- single deliverable into the existing media_file columns at build time
-- (chosen variant → optimized_file_name + truthful content_hash / file_size /
-- dimensions), so the cartridge artifact schema is unchanged and deployed
-- consumers are unaffected.
--
-- The `kind` vocabulary is an open registry (constants in MarqueeDataKit and
-- rows.js), not a CHECK constraint — a new kind is a registry entry, not a
-- migration. media_file's optimized_file_name / thumbnail_file_name columns
-- are frozen as read-compat mirrors: writers dual-write, readers prefer this
-- table.
--
-- First append-only migration since the 2026-07-23 baseline flatten: Surface
-- clients and legacy-published shows are live, so the baseline is no longer
-- editable in place.

CREATE TABLE media_file_variant (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  media_file_id INTEGER NOT NULL REFERENCES media_file(id) ON DELETE CASCADE,
  kind          TEXT    NOT NULL,            -- 'optimized' | 'webOptimized' | 'mask' | 'extract' | …
  file_name     TEXT    NOT NULL,            -- {uuid}.{ext} in Media/, same minting as every file
  content_type  TEXT,
  width         INTEGER,
  height        INTEGER,
  file_size     INTEGER,
  content_hash  TEXT,                        -- 'sha256:…' of THESE bytes
  codec         TEXT,
  created       INTEGER NOT NULL,
  updated       INTEGER NOT NULL
);

CREATE UNIQUE INDEX idx_media_file_variant_kind ON media_file_variant (media_file_id, kind);
CREATE UNIQUE INDEX idx_media_file_variant_name ON media_file_variant (file_name);
"""#)
        }
        // media_optimization — the automatic optimizer's per-(file, kind) ledger: ready / not_needed / failed with the receipt, so "already optimal" is durable and nothing reprocesses; authoring db only, cartridge builders drop it. Additive.
        migrator.registerMigration("v3-media-optimization") { db in
            try db.execute(sql: #"""
-- v3-media-optimization
-- The automatic optimizer's LEDGER: what was decided for each
-- (media_file, variant kind) — a rendition was produced ('ready'), the source
-- was already optimal and none is needed ('not_needed'), or the attempt
-- failed ('failed'). Durable on purpose: "don't try this one again" has to
-- survive a relaunch, a cloud pull on another machine, and the peer Studio,
-- and a media_file_variant row cannot carry it — file_name is NOT NULL and
-- unique, and a not-needed outcome has no file (the original already owns
-- that name).
--
-- AUTHORING (main db) ONLY. Cartridge builders DROP this table; the
-- deliverable is still resolved from media_file_variant, so the cartridge
-- artifact schema is unchanged and deployed consumers are unaffected.
--
-- `kind` uses the media_file_variant vocabulary ('optimized' |
-- 'webOptimized' | …). `status` is an open registry as well (constants in
-- MarqueeDataKit and rows.js), not a CHECK constraint. Only OUTCOMES are
-- recorded — "pending" is the absence of a row (or a retryable failure),
-- computed by the reader, so a crash mid-encode can never leave a stale
-- in-progress marker behind. `engine` names what decided (optimizer +
-- media foundation versions + preset); a changed engine string is how a
-- better encoder re-opens settled rows — deliberately, never automatically.
--
-- Additive (new table), so either peer ships independently.

CREATE TABLE media_optimization (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  media_file_id INTEGER NOT NULL REFERENCES media_file(id) ON DELETE CASCADE,
  kind          TEXT    NOT NULL,            -- variant kind the decision is about
  status        TEXT    NOT NULL,            -- 'ready' | 'not_needed' | 'failed'
  reason        TEXT,                        -- the optimizer's skip / failure text
  recipe        TEXT,                        -- the receipt, e.g. 'normalize →HEVC @SSIMU2≥90'
  floor         REAL,                        -- perceptual floor asked (SSIMULACRA2)
  score         REAL,                        -- floor achieved, when measured
  engine        TEXT,                        -- who decided: optimizer + foundation + preset
  attempts      INTEGER NOT NULL DEFAULT 0,  -- runs so far, incl. failures
  created       INTEGER NOT NULL,
  updated       INTEGER NOT NULL
);

CREATE UNIQUE INDEX idx_media_optimization_kind ON media_optimization (media_file_id, kind);
"""#)
        }
        // playlist_entry gains loop_clip / pause_on_entry / pause_on_completion / disabled — the Studio playlist engine's per-entry states, resolved at the advance boundary. Studio-only (directives govern Surface entry visibility); additive and defaulted.
        migrator.registerMigration("v4-entry-playback-states") { db in
            try db.execute(sql: #"""
-- v4-entry-playback-states
-- Four per-entry playback states for the STUDIO's playlist engine, authored as
-- icons on the Editor's rail rows:
--
--   loop_clip           when this entry becomes active it repeats instead of
--                       passing through — the engine hands the SAME entry back
--   pause_on_entry      the engine cues this entry and HOLDS rather than
--                       playing it, so the operator can take it from preview
--   pause_on_completion the engine holds at the END of this entry instead of
--                       falling through to the next
--   disabled            the engine skips this entry while looking for the next
--                       playable one (an explicit Take still plays it once,
--                       without clearing the flag — standby / "on call" content)
--
-- All four resolve at ONE point: when a duration completes and the engine is
-- asked for the next entry. That is why entry and completion are the same
-- question asked at a boundary ("hold here?" — yes if the outgoing entry says
-- on-completion or the incoming says on-entry), and why precedence needs no
-- rules: loop returns before the pause questions are asked, and disabled is
-- consumed while searching for the next playable entry.
--
-- STUDIO-ONLY BY DESIGN. Entry visibility at a venue is a DIRECTIVE concern,
-- so Surface neither reads nor needs these. They do ride along in screen
-- cartridges, because `playlist_entry` is carried there — which is harmless:
-- extra columns never break a reader, only missing ones do, and the legacy
-- cartridge producer is unaffected because nothing consumes them.
--
-- Additive and defaulted, so either peer ships independently.

ALTER TABLE playlist_entry ADD COLUMN loop_clip           INTEGER NOT NULL DEFAULT 0;
ALTER TABLE playlist_entry ADD COLUMN pause_on_entry      INTEGER NOT NULL DEFAULT 0;
ALTER TABLE playlist_entry ADD COLUMN pause_on_completion INTEGER NOT NULL DEFAULT 0;
ALTER TABLE playlist_entry ADD COLUMN disabled            INTEGER NOT NULL DEFAULT 0;
"""#)
        }
        // brand_style (portal address company/style/version, version pinned so a republish cannot silently restyle a signed-off show) + brand_style_item_id (the media_item holding this project's style.json) on project and session_set. Brand files travel as ordinary media because a player's media cache is a flat namespace whose prune deletes any directory the manifest does not name; the import rewrites style.json's file paths to deliverable names. Resolution: session_set ?? project ?? client default. Nullable, additive.
        migrator.registerMigration("v5-brand-style") { db in
            try db.execute(sql: #"""
-- v5-brand-style
-- Which style book a project — or one session set — is branded with.
--
-- Two columns per table, because they answer two different questions and
-- collapsing them would lose one:
--
--   brand_style          PROVENANCE: "company/style/version" exactly as the
--                        brand portal addresses it, e.g. "acme/acme-2026/3".
--                        The VERSION is part of it deliberately. A published
--                        version is immutable, so pinning one is what stops a
--                        later republish silently restyling a show that was
--                        signed off. It is also the only thing that can answer
--                        "which boards does this agreement touch" when a
--                        typeface licence lapses.
--
--   brand_style_item_id  RESOLUTION: the media_item holding this project's copy
--                        of style.json. The player needs a FILE, and it has no
--                        route from a portal address to one.
--
-- ⚠️ Why an item id rather than letting the player find the folder.
--
-- The delivered brand folder cannot survive a player's media cache: that cache
-- is a flat namespace keyed by deliverable file name, and its prune removes
-- every top-level entry the cartridge manifest does not list — a `brand/`
-- directory included. So brand files travel as ORDINARY MEDIA like everything
-- else, and the import rewrites style.json's `files` paths to the deliverable
-- names they were given. Then a player resolves faces through the manifest it
-- already holds, and the spec's folder stays what it was written to be: the
-- producer's layout, for portal storage and for the import to read.
--
-- Resolution order is session_set ?? project ?? the client's built-in default,
-- which is why both tables carry both columns.
--
-- Nullable and additive: every existing project and set is unbranded, which is
-- what they are today, and either peer ships independently.

ALTER TABLE project     ADD COLUMN brand_style         TEXT;
ALTER TABLE project     ADD COLUMN brand_style_item_id INTEGER REFERENCES media_item(id) ON DELETE SET NULL;
ALTER TABLE session_set ADD COLUMN brand_style         TEXT;
ALTER TABLE session_set ADD COLUMN brand_style_item_id INTEGER REFERENCES media_item(id) ON DELETE SET NULL;
"""#)
        }
        // media_item.brand_member — the style address a media item belongs to, so the cartridge's reachable closure can seed brand files. Without it v5's reference resolves to media the publish drops: a typeface is referenced by no playlist or session set, only by name inside style.json, which the closure does not walk. A column rather than a tag because a tag is user-editable and removing one would silently drop the fonts. Nullable, additive, partial index.
        migrator.registerMigration("v6-brand-member") { db in
            try db.execute(sql: #"""
-- v6-brand-member
-- Marks a media_item as a member of a delivered style book.
--
-- ⚠️ Without this the brand never reaches a player, and v5 alone does not fix
-- that. A cartridge carries the REACHABLE closure — media seeded from schedule
-- entries, playlists, playlist entries, and a session set's backing and logo. A
-- typeface is referenced by none of those. It is named only inside style.json,
-- which is a media file's CONTENTS and not something the closure walks.
--
-- So brand media would be imported, sit in the project, and be dropped at
-- publish: a style book that exists everywhere except on the sign.
--
-- The value is the style's portal address — "company/style/version", the same
-- string as project.brand_style — so the seed is a match rather than a
-- convention, and a project carrying two style books over time keeps them
-- apart.
--
-- ⚠️ A COLUMN RATHER THAN A TAG, deliberately. Tags are a user-facing feature
-- on the Editor's rail: a tag is exactly the kind of thing an operator can
-- remove while tidying, and removing this one would drop the fonts from the next
-- publish with nothing to say why until a board came up in the system face. This
-- is not theirs to edit.
--
-- Nullable and additive: every existing media item belongs to no style book,
-- which is what they are today.

ALTER TABLE media_item ADD COLUMN brand_member TEXT;

CREATE INDEX IF NOT EXISTS idx_media_item_brand_member
    ON media_item(brand_member) WHERE brand_member IS NOT NULL;
"""#)
        }
        // Studio Surface Author M1 (PRD 06 §6.1; Reference §2.4, STD-03, STD-04). screen_config / screen_location / screen_schedule_entry and screen_id take their surface_* names, with their two indexes rebuilt under surface names; project.backing_item_id (the default backing, RESTRICT) is added; playlist.backing_item_id / overlay_item_id, media_item.backing_item_id / overlay_item_id and playlist.shuffle are dropped. The four playlist_entry playback states and playlist.is_seamless_video stay: Studio Player state, never published. NOT additive — both peers ship it together; a v6 build opens a v7 show read-only via the supersession guard.
        migrator.registerMigration("v7-surface-author") { db in
            try db.execute(sql: #"""
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
"""#)
        }
        return migrator
    }
}
