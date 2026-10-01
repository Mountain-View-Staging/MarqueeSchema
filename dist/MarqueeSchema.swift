// GENERATED FILE — DO NOT EDIT.
// Source: MarqueeSchema/schema/migrations.json (+ schema/sql/*.sql)
// Regenerate: node tools/generate.mjs
// Checksum:   de8fabf56e7dfd0e993957aef034c99711ee5ad850684c4b68669d5682306541

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
    public static let checksum = "de8fabf56e7dfd0e993957aef034c99711ee5ad850684c4b68669d5682306541"

    /// Ordered, append-only.
    public static let knownIdentifiers: [String] = [
        "v1-baseline",
        "v2-media-variants",
        "v3-media-optimization",
        "v4-entry-playback-states",
        "v5-brand-style",
        "v6-brand-member",
        "v7-surface-author",
        "v8-published-revision",
        "v9-surface-status",
        "v10-surface-status-fields",
        "v11-device-orientation",
        "v12-one-schedule",
        "v13-emergency-screens-project-links",
        "v14-session-board-templates",
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
        // Studio Surface Author M1 (SCH-01, Reference §8.4/§15; STD-01 repair). project.published_revision — the per-show counter every project.db publish increments in the transaction that reads it and stamps into cartridge_meta.published_revision; surface cartridges keep surface_config.revision. Then the STD-01 repair: media_file.content_type and codec taken from the `original` rendition where the row differs (the pre-2026-09-26 optimized dual-write stamped the rendition's type; the importer named no codec). Rows with no original row are the backfill's, not this migration's. Additive and defaulted; either peer ships independently.
        migrator.registerMigration("v8-published-revision") { db in
            try db.execute(sql: #"""
-- v8-published-revision
-- Studio Surface Author M1, SCH-01 and the STD-01 repair (Platform Reference
-- v25.0.1 §8.4, §9.5, §15 rulings of 2026-09-26; plan r2 D-r2-11). Two changes,
-- one migration: the counter the project cartridge lacked, and the repair of
-- the rows the pre-STD-01 write path stamped wrongly.
--
-- 1. project.published_revision — a per-show counter, incremented by every
--    project.db publish in the same transaction that reads it, and written into
--    the artifact's cartridge_meta.published_revision. A surface cartridge
--    already carries surface_config.revision; only the project cartridge had no
--    counter, so it shipped 0 with generated_at as its freshness token. A
--    consumer's gate compares (published_revision, generated_at) (Cartridge
--    Spec §8.4), and the counter is what lets it tell a newer project.db from
--    a re-upload of the same one. NOT NULL DEFAULT 0, so an older peer's INSERT
--    of the project row still succeeds and its UPDATE writes around the column
--    (Architecture §2.3 R6). The publisher alone writes it, column-scoped and
--    +1: neither Studio's project record carries it into a whole-row update.
--
-- 2. media_file.content_type and codec, repaired from the `original` rendition.
--    media_file describes the IMPORTED file (STD-01, Cartridge Spec §4.6). Until
--    2026-09-26 the `optimized` dual-write in upsertVariant stamped the row's
--    content_type with the RENDITION's type — an optimized PNG read image/heic —
--    and the importer never named the codec of what it was given. The v25
--    writer reads the original rendition when there is one, so the wire was
--    already right; this makes the authoring row right too. A row whose
--    original names a different type takes that type; a row with no codec takes
--    the original's (COALESCE — a codec the row already names is kept, and an
--    original with no type cannot write NULL into a NOT NULL column). Rows with
--    no `original` row at all — imported before v2-media-variants and never
--    backfilled — are out of reach here: MediaService.backfillOriginalVariants
--    and the web's ensureOriginalRenditions create that row before a publish
--    and repair the parent then. `updated` is left alone: nothing was edited; a
--    wrong value was recorded and is now read correctly.
--
-- Additive: one defaulted column and one UPDATE. Either peer ships
-- independently (Architecture §2.3 R6). Foreign keys off is fine — nothing
-- here touches a key.
--
-- Rehearsed 2026-09-26 on copies of the four dev shows (foreign_key_check
-- empty, integrity_check ok on each): VP26 10 rows retyped and 21 codecs
-- filled, WFCHI2026X 5 retyped, DF26DEV 2 retyped and 2 rows with no original
-- left as they are, SESSDEV1 nothing to repair.

ALTER TABLE project ADD COLUMN published_revision INTEGER NOT NULL DEFAULT 0;

UPDATE media_file SET
  content_type = COALESCE(
    (SELECT v.content_type FROM media_file_variant v
      WHERE v.media_file_id = media_file.id AND v.kind = 'original'),
    content_type),
  codec = COALESCE(
    codec,
    (SELECT v.codec FROM media_file_variant v
      WHERE v.media_file_id = media_file.id AND v.kind = 'original'))
WHERE EXISTS (
  SELECT 1 FROM media_file_variant v
   WHERE v.media_file_id = media_file.id AND v.kind = 'original'
     AND (   (v.content_type IS NOT NULL AND v.content_type <> media_file.content_type)
          OR (media_file.codec IS NULL AND v.codec IS NOT NULL) )
);
"""#)
        }
        // Studio Delivery M2 (PRD 07 §5.6 F-06, §6.1, §6.4). surface_status — one row per location, the latest Surface status Studio holds for it, whichever path it came by (lan / cache / cloud): the device's lastUpdate, Studio's received_at, the committed cartridge's revision and generated_at, media held / total / missing / failed, the entry and set on screen, the last issue, app version and platform. location_id is the PRIMARY KEY and references surface_location(location_id) ON DELETE CASCADE (§6.4). surface_location.last_checked_at and last_pulled_revision move into it as path 'lan' rows and are dropped. Authoring only, never published. NOT additive for an older writer (its location record names the dropped columns) — both peers take it together; a v8 build opens a v9 show read-only via the supersession guard.
        migrator.registerMigration("v9-surface-status") { db in
            try db.execute(sql: #"""
-- v9-surface-status
-- Studio Delivery M2 (PRD 07 §5.6 F-06, §5.7 F-07, §6.1, §6.4; plan Phase 3
-- "Delivery M2"). One table, one move: where a Surface's status is kept, and
-- the two columns that were its first draft.
--
-- 1. surface_status — one row per location, the latest status report Studio
--    has for it, whichever path it came by (`path`: lan, cache, cloud). The
--    columns read the Surface Marquee App PRD §5.8 SurfaceStatus one for one:
--    the device's `last_update` (its last completed pass, ms), the committed
--    cartridge's (published_revision, generated_at), the media it holds / the
--    manifest total / missing / failed, the entry and rotation set on screen,
--    the last skip / hold / warning, and the app's version and platform. Beside
--    them Studio's own `received_at` and `path`, and `surface_code` so a row
--    still names its Surface when the location is re-assigned. Merging is the
--    store's rule, not the schema's: for each location the newest
--    `last_update` wins, whichever path (F-06).
--
--    location_id is the PRIMARY KEY and REFERENCES surface_location(location_id)
--    (TEXT NOT NULL UNIQUE there — a valid parent key) ON DELETE CASCADE, which
--    is §6.4: deleting a location deletes its status row, on either peer, with
--    no code. A status for a location the show does not have has no row to
--    join and is refused by the store (the PRD's "a spoofed post cannot change
--    anything but that location's status row" needs the row to exist first).
--
--    Authoring schema only, never published: both cartridge writers whitelist
--    their tables (CartridgeFormat.surfaceTables / SURFACE_TABLES), and neither
--    names this one.
--
-- 2. surface_location.last_checked_at and last_pulled_revision MOVE into it
--    (§6.1, last paragraph). They were the LAN check-in's first home (the
--    control channel's hello and ping, MarqueeStore.recordCheckIn), written by
--    Studio's LAN server alone. Each location that has a recorded check-in
--    becomes one status row: path 'lan' (that is the path they came by),
--    last_update and received_at both the check-in time (the check-in carried
--    one clock), published_revision the pulled revision, and every column a
--    check-in never reported left NULL — including `source`, which the Surface
--    reports and a check-in did not. A row whose check-in recorded no time is
--    not carried: last_update and received_at are NOT NULL, and a revision with
--    no date says nothing a Dashboard can show. (recordCheckIn always wrote
--    both, so today that is no row.) Then the two columns are dropped.
--
-- Additive for readers, not for writers: an older peer's SurfaceLocation
-- record names the two dropped columns in its INSERT and UPDATE, so a v8
-- build cannot write a location in a v9 show — the supersession guard
-- (Architecture §2.3 R2) opens it read-only. Both Studios take v9 in one
-- session, as they took v7.
--
-- DROP COLUMN needs SQLite ≥ 3.35 (the floor v7 set); neither column is
-- indexed, referenced or generated. Foreign keys off is fine: the INSERT below
-- reads its parent from the same table it references.
--
-- Rehearsed 2026-09-26 on copies of the four dev shows through both
-- migrators — see the commit and the schema CLAUDE.md.

CREATE TABLE surface_status (
  location_id        TEXT    PRIMARY KEY REFERENCES surface_location(location_id) ON DELETE CASCADE,
  surface_code       TEXT,                      -- the Surface's code, as it reported it
  path               TEXT    NOT NULL,          -- 'lan' | 'cache' | 'cloud': how Studio got it
  last_update        INTEGER NOT NULL,          -- the Surface's lastUpdate, unix ms
  received_at        INTEGER NOT NULL,          -- when Studio stored it, unix ms
  source             TEXT,                      -- the Surface's own source: 'lan' | 'cloud'
  published_revision INTEGER,                   -- committed cartridge
  generated_at       INTEGER,
  media_held         INTEGER,
  media_total        INTEGER,
  media_missing      INTEGER,
  media_failed       INTEGER,
  current_entry_id   INTEGER,
  current_set        TEXT,                      -- 'standard' | 'takeover'
  last_issue_code    TEXT,                      -- the last skip / hold / warning
  last_issue_at      INTEGER,
  app_version        TEXT,
  platform           TEXT                       -- 'macos' | 'ios' | 'windows' | 'linux'
);

INSERT INTO surface_status
  (location_id, surface_code, path, last_update, received_at, published_revision)
  SELECT sl.location_id, sc.surface_id, 'lan', sl.last_checked_at, sl.last_checked_at, sl.last_pulled_revision
  FROM surface_location sl
  JOIN surface_config sc ON sc.id = sl.config_id
  WHERE sl.last_checked_at IS NOT NULL
  ORDER BY sl.id;

ALTER TABLE surface_location DROP COLUMN last_checked_at;
ALTER TABLE surface_location DROP COLUMN last_pulled_revision;
"""#)
        }
        // Studio Delivery M3 (PRD 07 §5.6 F-06, §6.1; plan D-r2-21 a; Reference §15 2026-09-26). surface_status gains the DemoStation PRD §5.8's seven status fields as nullable columns — mode, screen_source, layout, pip_source, screen_capture, device_connected (0/1), surface_muted (0/1) — sent by a Surface with the mode (the macOS Surface) and NULL for every other, so both Studios show them from the row whichever path the report came by (LAN, cloud, a Cache's forwarding) instead of the Mac's live registry alone. Authoring only, never published. Additive and nullable; either peer ships independently.
        migrator.registerMigration("v10-surface-status-fields") { db in
            try db.execute(sql: #"""
-- v10-surface-status-fields
-- Studio Delivery M3 (PRD 07 §5.6 F-06, §6.1; plan r2 D-r2-21 (a), decided
-- 2026-09-26; Reference §15, the ruling of the same day). Seven nullable
-- columns on surface_status: the DemoStation's status fields.
--
-- The Surface Marquee App PRD §5.8 SurfaceStatus grew the DemoStation PRD
-- §5.8's seven fields in DS M2 (MarqueeNetworkKit e624dcd), sent by a Surface
-- with the mode — the macOS Surface — and absent from every other. v9's table
-- read the App PRD's fields one for one but had no column for these, so the
-- Mac showed them from its LAN server's live registry while a Surface was
-- connected and the web could not show them at all. From here on the row
-- carries them and both Studios show them from the row (D-r2-21 a), by
-- whichever path the report came — the LAN sink, the cloud reader (Delivery
-- M3), a Cache's forwarding (M4).
--
--   mode              'surface' | 'demoStation'
--   screen_source     'display' | 'usbCapture'          what feeds the screen zone
--   layout            'standard' | 'fullScreenMirror' | 'largeDevice'
--   pip_source        'miniPlayer' | 'device'           what the PIP zone shows
--   screen_capture    'ok' | 'noPermission' | 'failed'
--   device_connected  0 | 1                              an iPhone or iPad over USB
--   surface_muted     0 | 1                              the player's playlist audio
--
-- All nullable, no default: a report without the mode writes NULL to each,
-- which is what "absent from the wire" means on the row. The two booleans are
-- INTEGER 0/1, as every boolean in this schema (surface_config.archived,
-- playlist_entry.disabled). A bare check-in (hello / ping) never touches them.
--
-- Additive: an older peer's SurfaceStatusRecord INSERT names none of these and
-- its UPDATE writes around them (Architecture §2.3 R6), so either Studio ships
-- independently. Foreign keys off is fine — nothing here touches a key.
-- Authoring only, never published: both cartridge writers whitelist their
-- tables, and neither names surface_status.
--
-- Rehearsed 2026-09-26 on copies of the four dev shows through both migrators
-- — see the commit and the schema CLAUDE.md.

ALTER TABLE surface_status ADD COLUMN mode             TEXT;
ALTER TABLE surface_status ADD COLUMN screen_source    TEXT;
ALTER TABLE surface_status ADD COLUMN layout           TEXT;
ALTER TABLE surface_status ADD COLUMN pip_source       TEXT;
ALTER TABLE surface_status ADD COLUMN screen_capture   TEXT;
ALTER TABLE surface_status ADD COLUMN device_connected INTEGER;
ALTER TABLE surface_status ADD COLUMN surface_muted    INTEGER;
"""#)
        }
        // ORI-02 (plan r2 D-r2-24; Reference §15 2026-09-27; PRDs 06 §5.7 and 07 §5.7 amended). A device's orientation is the device's: surface_location.orientation (the mount) is dropped — a Surface renders Automatic, or Landscape / Portrait set on the device, a publish never changes it, and the Cartridge Specification retired the column (9285b01), so both writers stop emitting it; surface_status gains orientation (TEXT, nullable, 'portrait' | 'landscape'), the orientation a Surface reports it renders (SurfaceStatus.orientation, MarqueeNetworkKit 6729aeb), which is where the Dashboard reads it. No data moves: a mount is not a report. NOT additive for an older writer (its location record names the dropped column in INSERT and UPDATE) — both peers take it together; a v10 build opens a v11 show read-only via the supersession guard.
        migrator.registerMigration("v11-device-orientation") { db in
            try db.execute(sql: #"""
-- v11-device-orientation
-- ORI-02 (plan r2 D-r2-24, decided 2026-09-27; Reference §15, the ruling of
-- the same day; PRDs 06 §5.7 and 07 §5.7 amended). A device's orientation is
-- the device's: a location stops carrying one, and a status report carries
-- the one the device renders.
--
-- 1. surface_location.orientation is DROPPED. It was the mount ('portrait' |
--    'landscape'), authored in both Studios' location editors and published in
--    the surface cartridge, where a Surface adopted it with its location. It
--    was authored before a Surface could choose its orientation: a Surface now
--    renders Automatic (the shape of the display it drives) by default, or
--    Landscape / Portrait set on the device, and a publish never changes it
--    (Cartridge Specification §6, 9285b01). The mount and the device could
--    disagree, and the device's choice is the one that is true. A location
--    identifies an installation — its status row, the location picker, the
--    publish gate — and nothing more. The specification retired the column
--    from §4.4 (a Loader ignores it, without a warning, in a cartridge that
--    still has it), and both cartridge writers stop emitting it with this
--    migration.
--
-- 2. surface_status.orientation is ADDED: the orientation the Surface reports
--    it renders ('portrait' | 'landscape' — the Surface App PRD §5.8
--    SurfaceStatus `orientation`, MarqueeNetworkKit 6729aeb, which the Worker's
--    check-in accepts since micro-services ac6deae). This is where the
--    Dashboard reads a sign's orientation (PRD 07 §5.7). Nullable, no default:
--    a report from a Surface that predates it carries none, a bare check-in
--    (hello / ping) never touches it, and the Dashboard shows it blank.
--
-- No data moves. A mount is not a report: copying it into surface_status
-- would claim an orientation no device said it renders.
--
-- NOT additive for an older writer: a v10 SurfaceLocation record names
-- `orientation` in its INSERT and UPDATE, so a v10 build cannot write a
-- location in a v11 show — the supersession guard (Architecture §2.3 R2) opens
-- it read-only. Both Studios take v11 in one session, as they took v7 and v9.
--
-- DROP COLUMN needs SQLite ≥ 3.35 (the floor v7 set). The column is not
-- indexed (idx_surface_location_config is config_id alone), keyed, referenced,
-- generated, or named by a CHECK, a trigger or a view; the rows keep their
-- ids, and surface_status keeps its reference to surface_location(location_id).
-- Foreign keys off is fine: nothing here touches a key. Authoring only:
-- surface_status is never published (both cartridge writers whitelist their
-- tables, and neither names it).
--
-- Rehearsed 2026-09-27 on copies of the four dev shows through both migrators
-- — see the commit and the schema CLAUDE.md.

ALTER TABLE surface_location DROP COLUMN orientation;

ALTER TABLE surface_status ADD COLUMN orientation TEXT;   -- 'portrait' | 'landscape', as the device reports it
"""#)
        }
        // ONE-02 (plan r2 D-r2-30, decided 2026-09-27; Reference §15; Cartridge Specification §4.4/§5.1 at d54bd88, spec PR #12). One schedule per surface: surface_schedule_entry.slot becomes 'playlist' | 'demo_station'. By reading (b) a config keeps its 'landscape' entries when it has any, else its 'portrait' ones, as 'playlist'; the other orientation's entries of a config that had both are dropped. A demo_station entry is branding only (reading (a): the picture-in-picture plays the same playlist in the opposite orientation), so its PIP playlist is dropped and the CHECK — now the wire's exactly — forbids one. The table is rebuilt (renamed aside, created, filled, dropped), keeping ids and the AUTOINCREMENT sequence; idx_surface_sched_slot is created again. NOT additive for an older writer (a v11 build writes 'portrait' / 'landscape' rows the CHECK refuses) — both peers take it together; a v11 build opens a v12 show read-only via the supersession guard.
        migrator.registerMigration("v12-one-schedule") { db in
            try db.execute(sql: #"""
-- v12-one-schedule
-- ONE-02 (plan r2 D-r2-30, decided 2026-09-27; Reference §15; the Cartridge
-- Specification's §4.4 and §5.1 at d54bd88, spec PR #12). One schedule per
-- surface: a surface schedules playlists in ONE slot, not a portrait and a
-- landscape one. A playlist already carries both orientations in its items'
-- slots, and a device plays the scheduled playlist with the files of the
-- orientation it renders (D-r2-24). Two surfaces that need different content
-- per orientation are two configs.
--
-- 1. surface_schedule_entry.slot becomes 'playlist' | 'demo_station'. The
--    playlist rows are carried by reading (b), ratified by the operator: a
--    config keeps its 'landscape' entries when it has any, else its
--    'portrait' ones, as 'playlist'. The other orientation's entries of a
--    config that had both are dropped (the rehearsal lists them). Ids,
--    timestamps, playlists and clocks are kept.
--
-- 2. A 'demo_station' entry is branding only (reading (a)): the DemoStation's
--    picture-in-picture plays the SAME scheduled playlist, with the files of
--    the opposite orientation (spec §5.11). The pre-v25 PIP playlist a demo
--    row could carry (D3) is dropped: its playlist_id becomes NULL, and the
--    CHECK now forbids one — the wire's CHECK, exactly.
--
-- 3. The CHECK changes, so the table is rebuilt: renamed aside, created under
--    its name with the new CHECK, filled, the old one dropped, and the index
--    idx_surface_sched_slot (config_id, slot, timestamp) created again. No
--    table references surface_schedule_entry, so the rename rewrites nothing
--    on either SQLite (Apple's defaults legacy_alter_table ON; the v7 note in
--    the schema CLAUDE.md), and the table's own references are its new DDL's.
--    AUTOINCREMENT keeps its promise across the rebuild: the new table's
--    sequence is the old one's, so a dropped entry's id is never reused.
--
-- Values other than 'portrait', 'landscape' and 'demo_station' never passed the
-- v7 CHECK, so there are none to carry.
--
-- NOT additive for an older writer: a v11 build writes 'portrait' and
-- 'landscape' rows, which the new CHECK refuses — both peers take v12 in one
-- cut-over (D-r2-26), and a v11 build opens a v12 show read-only through the
-- supersession guard. format_version stays 25.0.1 (reading (c)).
--
-- Rehearsed on copies of the four dev shows through both migrators — see the
-- commit and the schema CLAUDE.md.

ALTER TABLE surface_schedule_entry RENAME TO surface_schedule_entry_v11;

CREATE TABLE surface_schedule_entry (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  config_id          INTEGER NOT NULL REFERENCES surface_config(id) ON DELETE CASCADE,
  slot               TEXT    NOT NULL,            -- 'playlist' | 'demo_station'
  timestamp          INTEGER NOT NULL,            -- most-recent <= now wins, per slot
  playlist_id        INTEGER REFERENCES playlist(id)   ON DELETE RESTRICT,  -- the playlist slot's; NULL = an authored blank
  background_item_id INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (behind)
  overlay_item_id    INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (front)
  created            INTEGER NOT NULL,
  updated            INTEGER NOT NULL,
  -- A playlist entry carries only a playlist (NULL: an authored blank). A demo
  -- entry carries branding only — the picture-in-picture plays the one
  -- schedule's playlist; an overlay still requires a background, and all-NULL =
  -- exit demo mode. The wire's CHECK (Cartridge Specification §4.4).
  CHECK (
    ( slot = 'playlist'
        AND background_item_id IS NULL AND overlay_item_id IS NULL )
    OR
    ( slot = 'demo_station'
        AND playlist_id IS NULL
        AND ( background_item_id IS NOT NULL OR overlay_item_id IS NULL ) )
  )
);

INSERT INTO surface_schedule_entry
  (id, config_id, slot, timestamp, playlist_id, background_item_id, overlay_item_id, created, updated)
  SELECT e.id, e.config_id,
         CASE WHEN e.slot = 'demo_station' THEN 'demo_station' ELSE 'playlist' END,
         e.timestamp,
         CASE WHEN e.slot = 'demo_station' THEN NULL ELSE e.playlist_id END,
         e.background_item_id, e.overlay_item_id, e.created, e.updated
  FROM surface_schedule_entry_v11 e
  WHERE e.slot = 'demo_station'
     OR e.slot = 'landscape'
     OR ( e.slot = 'portrait'
          AND NOT EXISTS ( SELECT 1 FROM surface_schedule_entry_v11 l
                           WHERE l.config_id = e.config_id AND l.slot = 'landscape' ) )
  ORDER BY e.id;

-- The new table's sequence is the old one's (AUTOINCREMENT: never reuse an id).
DELETE FROM sqlite_sequence WHERE name = 'surface_schedule_entry';
INSERT INTO sqlite_sequence (name, seq)
  SELECT 'surface_schedule_entry', seq FROM sqlite_sequence WHERE name = 'surface_schedule_entry_v11';

DROP TABLE surface_schedule_entry_v11;

CREATE INDEX idx_surface_sched_slot ON surface_schedule_entry (config_id, slot, timestamp);
"""#)
        }
        // The operator, 2026-09-28. Two project-level additions, authoring only (the wire and every Surface client are unchanged). emergency_screen: an ordered array of { name, media_item_id }; at publish each writer appends one entry per emergency screen to the end of every playlist a surface cartridge carries (reserved ids 1e15 + playlist_id * 1e6 + id), so the items ride every media manifest and sit dormant (no directive). emergency_screen_directive: what Studio writes to switch one on (ON at 12:00:00 AM of the current venue day) or off; each writer copies it onto that screen's entry in every playlist as a takeover directive (spec §5.4, §5.5). project_link: an ordered array of { name, uri } for project documents and folders, never published. Additive; both peers take it in lock-step (D-r2-26).
        migrator.registerMigration("v13-emergency-screens-project-links") { db in
            try db.execute(sql: #"""
-- v13-emergency-screens-project-links
-- Two project-level additions (the operator, 2026-09-28). Authoring only: the
-- Cartridge Specification's wire is unchanged, and no Surface client changes.
--
-- 1. EMERGENCY SCREENS. An ordered array of { name, media item }. At publish,
--    each writer (MarqueeDataKit, the web's cartridge.js) appends one entry per
--    emergency screen to the END of every playlist a surface cartridge carries,
--    in `position` order, so the items ride every cartridge's media manifest and
--    every device holds them ahead of time. An entry with no directive never
--    plays (spec §5.4), so they sit dormant.
--
--    An emergency screen is switched on by an emergency_screen_directive — what
--    Studio's UI writes: ON at 12:00:00 AM of the current venue day, so it is in
--    force the moment a device commits the cartridge. The writer copies each such
--    directive onto that screen's entry in every playlist as a TAKEOVER directive,
--    and a Surface cuts to it as it cuts to any takeover (spec §5.5, §5.9).
--    Directives are day-scoped (spec §5.4): an ON lapses when its venue day ends.
--    OFF (on_screen 0) clears it.
--
--    The rows a writer adds get ids in a reserved range, stable across publishes:
--    1e15 + playlist_id * 1e6 + the emergency screen's (or directive's) id — above
--    any AUTOINCREMENT id, inside JavaScript's exact integers.
--
-- 2. PROJECT LINKS. An ordered array of { name, uri }: project documents and
--    file folders, for the people running the show. Never published — no
--    cartridge carries it (a cartridge sits in a public bucket).
--
-- Additive (three new tables), but both peers take it in lock-step (D-r2-26): a
-- v12 build opens a v13 show read-only through the supersession guard.

CREATE TABLE emergency_screen (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  name          TEXT    NOT NULL,
  media_item_id INTEGER NOT NULL REFERENCES media_item(id) ON DELETE RESTRICT,
  position      INTEGER NOT NULL,            -- the array's order; and the order at the end of every playlist
  created       INTEGER NOT NULL,
  updated       INTEGER NOT NULL
);

CREATE INDEX idx_emergency_screen_position ON emergency_screen (position);

CREATE TABLE emergency_screen_directive (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  emergency_screen_id INTEGER NOT NULL REFERENCES emergency_screen(id) ON DELETE CASCADE,
  timestamp           INTEGER NOT NULL,      -- Unix ms; the UI writes 12:00:00 AM of the current venue day
  on_screen           INTEGER NOT NULL,      -- 1 = on (a takeover), 0 = cleared
  timezone            TEXT,                  -- authoring context only, as directive.timezone
  created             INTEGER NOT NULL,
  updated             INTEGER NOT NULL
);

CREATE INDEX idx_emergency_screen_directive_screen ON emergency_screen_directive (emergency_screen_id, timestamp);

CREATE TABLE project_link (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  name     TEXT    NOT NULL,
  uri      TEXT    NOT NULL,
  position INTEGER NOT NULL,                 -- the array's order
  created  INTEGER NOT NULL,
  updated  INTEGER NOT NULL
);

CREATE INDEX idx_project_link_position ON project_link (position);
"""#)
        }
        // PRD 14 (2026-10-01; Cartridge Specification §5.15 at 46cf736, spec PR #15). Session board templates: project and session_set gain template_item_id (→ media_item, ON DELETE SET NULL; the package, one application/zip media file; the set's overrides the Show's) and template_settings (JSON { "vars": { name: string } }, following the pointer they sit beside). session_set.render_modes and schedule_template are DROPPED: which layouts a sign shows is the device's setting (its board variant), and the layout diff never had a reader. NOT additive (the operator's no-legacy rule, 2026-10-01): both peers take it in one cut-over; a v13 build opens a v14 show read-only. The wire DDL changes with it.
        migrator.registerMigration("v14-session-board-templates") { db in
            try db.execute(sql: #"""
-- v14-session-board-templates
-- Session board templates (PRD 14, 2026-10-01; the Cartridge Specification's §5.15 at
-- 46cf736, spec PR #15). A session board is rendered from a TEMPLATE PACKAGE — a zip of
-- template.json, the page, its layouts, styles, fonts and a small engine — that the Show,
-- or one session set, names; a Surface carries a built-in default for a Show that names
-- none. The package rides a cartridge as one media file of type application/zip, in the
-- portrait slot of a media item, taken as the manifest names it (never decoded, never
-- renditioned) and wanted on every lane.
--
-- 1. project.template_item_id / session_set.template_item_id: the media item holding the
--    package; the set's overrides the Show's, as a backing does. ON DELETE SET NULL: a
--    template item is archive-not-delete in the UI, and a deleted one leaves the pointer
--    empty rather than refusing.
-- 2. project.template_settings / session_set.template_settings: JSON
--    { "vars": { name: string } } — the Show's values for the variables the template
--    declares, passed through to the template's data document. The settings follow the
--    pointer they sit beside (a set with its own template uses its own; a set without one
--    uses the Show's template with the Show's settings).
-- 3. session_set.render_modes and session_set.schedule_template are DROPPED. Which of a
--    template's layouts a sign shows (now / next, the schedule, or both) is the DEVICE's
--    setting, beside its orientation, never authored; and schedule_template (a layout diff
--    no player ever read) has no successor. No data moves: a set's authored mode was a
--    renderer's choice that the device now makes.
--
-- NOT additive (two columns removed) — the operator's rule of 2026-10-01: no legacy
-- support, the format provides what the app does, not what it did. Both peers take v14 in
-- one cut-over (D-r2-26); a v13 build opens a v14 show read-only through the supersession
-- guard. The wire DDL (spec §4.3, §4.7) changes with it; format_version stays 25.0.1.

ALTER TABLE project ADD COLUMN template_item_id INTEGER REFERENCES media_item(id) ON DELETE SET NULL;
ALTER TABLE project ADD COLUMN template_settings TEXT;
ALTER TABLE session_set ADD COLUMN template_item_id INTEGER REFERENCES media_item(id) ON DELETE SET NULL;
ALTER TABLE session_set ADD COLUMN template_settings TEXT;
ALTER TABLE session_set DROP COLUMN render_modes;
ALTER TABLE session_set DROP COLUMN schedule_template;
"""#)
        }
        return migrator
    }
}
