// GENERATED FILE — DO NOT EDIT.
// Source: MarqueeSchema/schema/migrations.json (+ schema/sql/*.sql)
// Regenerate: node tools/generate.mjs
// Checksum:   9c801c82e5b4761e0e5c3e167e66ca341948e272799c90082cdae81c150bd15a

export const MIGRATION_TABLE = "grdb_migrations"
export const SCHEMA_CHECKSUM = "9c801c82e5b4761e0e5c3e167e66ca341948e272799c90082cdae81c150bd15a"

/** Ordered, append-only. Index position is meaningful; never reorder. */
export const MIGRATIONS = Object.freeze([
    // The full Marquee project schema as a single baseline, flattened from the former v1..v14 append-only history (2026-07-23). Dev-mode edit 2026-08-15: sessions (session/session_set/session_set_entry), playlist_entry resource_type expansion to session sets, demo-slot playlist (SPEC-sqlite-cartridge-deployment).
    { identifier: "v1-baseline", sql: "-- v1-baseline\n-- The full Marquee project schema as a single baseline.\n--\n-- Collapsed from the former v1..v14 append-only history (2026-07-23): nothing\n-- consumes these databases with a shipped MVP client yet, so the migration\n-- trail was flattened into one baseline. Until an MVP client exists this file\n-- may be edited in place; once one ships, return to append-only (add v2-… etc.)\n-- rather than editing the baseline, so deployed databases can still migrate.\n--\n-- Dev-mode edit 2026-08-15 (SPEC-sqlite-cartridge-deployment, legacy Studio\n-- convergence): sessions join the schema (session / session_set /\n-- session_set_entry), playlist_entry generalizes to non-media resources via the\n-- forward-declared resource_type vocabulary, and the demo_station slot may\n-- carry a playlist (PIP content) alongside its branding.\n\nCREATE TABLE project (\n  id                        INTEGER PRIMARY KEY AUTOINCREMENT,\n  cloud_uid                 TEXT    NOT NULL,\n  name                      TEXT    NOT NULL,\n  created                   INTEGER NOT NULL,\n  updated                   INTEGER NOT NULL,\n  retain_originals          INTEGER NOT NULL DEFAULT 1,\n  timezone                  TEXT,\n  project_code              TEXT,\n  show_wallpaper_item_id    INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  desktop_wallpaper_item_id INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  edit_code_required        INTEGER NOT NULL DEFAULT 0\n);\n\nCREATE TABLE media_file (\n  id                  INTEGER PRIMARY KEY AUTOINCREMENT,\n  source_file_name    TEXT    NOT NULL UNIQUE,\n  thumbnail_file_name TEXT,\n  content_type        TEXT    NOT NULL,\n  width               INTEGER,\n  height              INTEGER,\n  orientation         TEXT,\n  aspect_ratio        REAL,\n  intrinsic_duration  REAL,\n  file_size           INTEGER,\n  source_hash         TEXT,\n  content_hash        TEXT,\n  codec               TEXT,\n  color_space         TEXT,\n  was_converted       INTEGER NOT NULL DEFAULT 0,\n  original_type       TEXT,\n  original_file_name  TEXT,\n  source_document     TEXT,\n  source              TEXT,\n  created             INTEGER NOT NULL,\n  updated             INTEGER NOT NULL,\n  optimized_file_name TEXT\n);\n\nCREATE UNIQUE INDEX idx_media_file_source_hash ON media_file (source_hash);\n\nCREATE INDEX idx_media_file_orientation ON media_file (orientation);\n\nCREATE TABLE media_item (\n  id                INTEGER PRIMARY KEY AUTOINCREMENT,\n  name              TEXT    NOT NULL,\n  portrait_file_id  INTEGER REFERENCES media_file(id) ON DELETE RESTRICT,\n  landscape_file_id INTEGER REFERENCES media_file(id) ON DELETE RESTRICT,\n  display_duration  REAL,\n  system_generated  INTEGER NOT NULL DEFAULT 0,\n  audio_priority    TEXT,\n  backing_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  overlay_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  archived          INTEGER NOT NULL DEFAULT 0,\n  created           INTEGER NOT NULL,\n  updated           INTEGER NOT NULL,\n  CHECK (portrait_file_id IS NOT NULL OR landscape_file_id IS NOT NULL)\n);\n\nCREATE TABLE tag (\n  id      INTEGER PRIMARY KEY AUTOINCREMENT,\n  name    TEXT    NOT NULL,\n  color   TEXT,\n  created INTEGER NOT NULL\n);\n\nCREATE UNIQUE INDEX idx_tag_name ON tag (name COLLATE NOCASE);\n\nCREATE TABLE tag_assignment (\n  tag_id      INTEGER NOT NULL REFERENCES tag(id) ON DELETE CASCADE,\n  entity_type TEXT    NOT NULL,\n  entity_id   INTEGER NOT NULL,\n  PRIMARY KEY (tag_id, entity_type, entity_id)\n);\n\nCREATE INDEX idx_tag_assignment_entity ON tag_assignment (entity_type, entity_id);\n\nCREATE INDEX idx_tag_assignment_tag    ON tag_assignment (tag_id, entity_type);\n\nCREATE UNIQUE INDEX idx_media_file_optimized ON media_file (optimized_file_name);\n\n-- Sessions: conference/agenda content rendered by the player (schedule boards,\n-- room signs). Imported from external integrations, so the variable shapes\n-- (presenters, attributes incl. multi-room time attributes, the layer-2\n-- schedule_template diff) stay JSON-tolerant TEXT rather than fully relational —\n-- they are consumed opaquely by the renderer.\nCREATE TABLE session (\n  id          INTEGER PRIMARY KEY AUTOINCREMENT,\n  name        TEXT    NOT NULL,\n  abstract    TEXT,\n  presenters  TEXT,             -- JSON array\n  attributes  TEXT,             -- JSON array (vendor attributes; legacy producers may include time attributes)\n  source_id   TEXT,             -- vendor session id; NULL = manually authored\n  source_type TEXT,             -- provider discriminator, e.g. 'rainfocus' | 'spreadsheet'\n  source_name TEXT,             -- provider display name at import time\n  created     INTEGER NOT NULL,\n  updated     INTEGER NOT NULL\n);\n\nCREATE INDEX idx_session_source ON session (source_id);\n\nCREATE TABLE session_set (\n  id                INTEGER PRIMARY KEY AUTOINCREMENT,\n  name              TEXT    NOT NULL,\n  render_modes      TEXT    NOT NULL DEFAULT '[\"simple\"]',   -- JSON array\n  duration          REAL    NOT NULL DEFAULT 8,              -- seconds per board page\n  backing_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  logo_item_id      INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  schedule_template TEXT,       -- JSON diff vs the Surface baseline; absent = baseline\n  source_id         TEXT,       -- vendor room id; NULL = manually authored set\n  source_name       TEXT,       -- vendor room display name at import time\n  created           INTEGER NOT NULL,\n  updated           INTEGER NOT NULL\n);\n\n-- A session's membership in a set, at a specific time window. session_time_id\n-- distinguishes multiple time slots of the same session (multi-room);\n-- source_room_id records which vendor room minted the slot so a multi-room\n-- sync can reconcile per room without pruning its siblings.\nCREATE TABLE session_set_entry (\n  id              INTEGER PRIMARY KEY AUTOINCREMENT,\n  session_set_id  INTEGER NOT NULL REFERENCES session_set(id) ON DELETE CASCADE,\n  session_id      INTEGER NOT NULL REFERENCES session(id)     ON DELETE RESTRICT,\n  session_time_id TEXT,\n  start_time      INTEGER NOT NULL,\n  end_time        INTEGER NOT NULL,\n  source_room_id  TEXT,\n  room_name       TEXT,\n  created         INTEGER NOT NULL,\n  updated         INTEGER NOT NULL\n);\n\nCREATE INDEX idx_session_set_entry_set ON session_set_entry (session_set_id, start_time);\n\n-- Integration provider configuration (credentials, cached room catalog, sync\n-- bookkeeping) as an opaque JSON blob per provider. Authoring-side only: it\n-- travels with the project database so the team shares one configuration, and\n-- every cartridge kind drops this table before publishing.\nCREATE TABLE integration (\n  id       INTEGER PRIMARY KEY AUTOINCREMENT,\n  provider TEXT    NOT NULL UNIQUE,\n  config   TEXT    NOT NULL DEFAULT '{}',   -- JSON object\n  created  INTEGER NOT NULL,\n  updated  INTEGER NOT NULL\n);\n\nCREATE TABLE playlist (\n  id                INTEGER PRIMARY KEY AUTOINCREMENT,\n  name              TEXT    NOT NULL,\n  shuffle           INTEGER NOT NULL DEFAULT 0,\n  is_seamless_video INTEGER NOT NULL DEFAULT 0,\n  backing_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  overlay_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  archived          INTEGER NOT NULL DEFAULT 0,\n  created           INTEGER NOT NULL,\n  updated           INTEGER NOT NULL\n);\n\n-- An entry plays a resource; resource_type is the open-vocabulary discriminator\n-- (forward-declared in v7 of the pre-baseline history — \"today only 'media_item'\n-- resolves\"; 'session_set' is its first expansion, 2026-08-15). The implication\n-- CHECKs pin integrity for the known types without closing the vocabulary.\nCREATE TABLE playlist_entry (\n  id                   INTEGER PRIMARY KEY AUTOINCREMENT,\n  playlist_id          INTEGER NOT NULL REFERENCES playlist(id) ON DELETE CASCADE,\n  media_item_id        INTEGER REFERENCES media_item(id)  ON DELETE RESTRICT,\n  session_set_id       INTEGER REFERENCES session_set(id) ON DELETE RESTRICT,\n  position             INTEGER NOT NULL,\n  created              INTEGER NOT NULL,\n  updated              INTEGER NOT NULL,\n  resource_type        TEXT    NOT NULL DEFAULT 'media_item',\n  start_time_portrait  REAL,\n  end_time_portrait    REAL,\n  start_time_landscape REAL,\n  end_time_landscape   REAL,\n  CHECK (resource_type <> 'media_item'  OR media_item_id  IS NOT NULL),\n  CHECK (resource_type <> 'session_set' OR session_set_id IS NOT NULL)\n);\n\nCREATE INDEX idx_playlist_entry_order ON playlist_entry (playlist_id, position);\n\nCREATE INDEX idx_playlist_entry_item  ON playlist_entry (media_item_id);\n\nCREATE TABLE directive (\n  id         INTEGER PRIMARY KEY AUTOINCREMENT,\n  entry_id   INTEGER NOT NULL REFERENCES playlist_entry(id) ON DELETE CASCADE,\n  type       TEXT    NOT NULL,   -- 'standard' | 'takeover'\n  timestamp  INTEGER NOT NULL,\n  on_screen  INTEGER NOT NULL,\n  timezone   TEXT,\n  created    INTEGER NOT NULL,\n  updated    INTEGER NOT NULL\n);\n\nCREATE INDEX idx_directive_entry ON directive (entry_id, timestamp);\n\nCREATE TABLE screen_config (\n  id                 INTEGER PRIMARY KEY AUTOINCREMENT,\n  name               TEXT    NOT NULL,\n  revision           INTEGER NOT NULL DEFAULT 0,   -- monotonic; bumped on any schedule change\n  archived           INTEGER NOT NULL DEFAULT 0,\n  created            INTEGER NOT NULL,\n  updated            INTEGER NOT NULL,\n  screen_id          TEXT,\n  published_revision INTEGER,\n  published_at       INTEGER\n);\n\nCREATE TABLE screen_location (\n  id                   INTEGER PRIMARY KEY AUTOINCREMENT,\n  config_id            INTEGER NOT NULL REFERENCES screen_config(id) ON DELETE CASCADE,\n  location_id          TEXT    NOT NULL UNIQUE,   -- globally unique real-world id\n  orientation          TEXT    NOT NULL,          -- 'portrait' | 'landscape' (the mount)\n  label                TEXT,\n  last_checked_at      INTEGER,                   -- unix ms; \"is it online?\"\n  last_pulled_revision INTEGER,                   -- vs config.revision; \"needs update?\"\n  created              INTEGER NOT NULL,\n  updated              INTEGER NOT NULL\n);\n\nCREATE INDEX idx_screen_code_config ON screen_location (config_id);\n\nCREATE TABLE screen_schedule_entry (\n  id                 INTEGER PRIMARY KEY AUTOINCREMENT,\n  config_id          INTEGER NOT NULL REFERENCES screen_config(id) ON DELETE CASCADE,\n  slot               TEXT    NOT NULL,            -- 'portrait' | 'landscape' | 'demo_station'\n  timestamp          INTEGER NOT NULL,            -- most-recent <= now wins, per slot\n  playlist_id        INTEGER REFERENCES playlist(id)   ON DELETE RESTRICT,  -- portrait/landscape payload\n  background_item_id INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (behind)\n  overlay_item_id    INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (front)\n  created            INTEGER NOT NULL,\n  updated            INTEGER NOT NULL,\n  -- Playlist slots carry only a playlist. Demo slots carry branding and MAY\n  -- carry a playlist (PIP content, rendered by the consumer at the opposite\n  -- orientation — 2026-08-15, SPEC-sqlite-cartridge-deployment D3); an overlay\n  -- still requires a background, and all-NULL = blank = exit demo mode.\n  CHECK (\n    ( slot IN ('portrait','landscape')\n        AND background_item_id IS NULL AND overlay_item_id IS NULL )\n    OR\n    ( slot = 'demo_station'\n        AND ( background_item_id IS NOT NULL OR overlay_item_id IS NULL ) )\n  )\n);\n\nCREATE INDEX idx_screen_sched_slot ON screen_schedule_entry (config_id, slot, timestamp);\n\nCREATE TABLE project_days (\n  id         INTEGER PRIMARY KEY AUTOINCREMENT,\n  day        TEXT    NOT NULL UNIQUE,\n  start_time INTEGER NOT NULL,\n  end_time   INTEGER NOT NULL,\n  created    INTEGER NOT NULL,\n  updated    INTEGER NOT NULL\n);\n\nCREATE INDEX idx_project_day_start ON project_days (start_time);\n" },
    // media_file_variant — MediaFile children (optimized/webOptimized/mask/extract/…), authoring db only; cartridge builders drop it and resolve one deliverable into the existing media_file columns, so the cartridge artifact schema is unchanged. First append-only migration since the baseline flatten.
    { identifier: "v2-media-variants", sql: "-- v2-media-variants\n-- MediaFile children: alternate representations of the same content —\n-- optimized, webOptimized, mask, extract, and future kinds — each a real\n-- file on disk, with the parent media_file row aware of them.\n--\n-- AUTHORING (main db) ONLY. Cartridge builders DROP this table and resolve a\n-- single deliverable into the existing media_file columns at build time\n-- (chosen variant → optimized_file_name + truthful content_hash / file_size /\n-- dimensions), so the cartridge artifact schema is unchanged and deployed\n-- consumers are unaffected.\n--\n-- The `kind` vocabulary is an open registry (constants in MarqueeDataKit and\n-- rows.js), not a CHECK constraint — a new kind is a registry entry, not a\n-- migration. media_file's optimized_file_name / thumbnail_file_name columns\n-- are frozen as read-compat mirrors: writers dual-write, readers prefer this\n-- table.\n--\n-- First append-only migration since the 2026-07-23 baseline flatten: Surface\n-- clients and legacy-published shows are live, so the baseline is no longer\n-- editable in place.\n\nCREATE TABLE media_file_variant (\n  id            INTEGER PRIMARY KEY AUTOINCREMENT,\n  media_file_id INTEGER NOT NULL REFERENCES media_file(id) ON DELETE CASCADE,\n  kind          TEXT    NOT NULL,            -- 'optimized' | 'webOptimized' | 'mask' | 'extract' | …\n  file_name     TEXT    NOT NULL,            -- {uuid}.{ext} in Media/, same minting as every file\n  content_type  TEXT,\n  width         INTEGER,\n  height        INTEGER,\n  file_size     INTEGER,\n  content_hash  TEXT,                        -- 'sha256:…' of THESE bytes\n  codec         TEXT,\n  created       INTEGER NOT NULL,\n  updated       INTEGER NOT NULL\n);\n\nCREATE UNIQUE INDEX idx_media_file_variant_kind ON media_file_variant (media_file_id, kind);\nCREATE UNIQUE INDEX idx_media_file_variant_name ON media_file_variant (file_name);\n" },
].map(Object.freeze))

export const KNOWN_IDENTIFIERS = Object.freeze(MIGRATIONS.map((m) => m.identifier))

/**
 * Identifiers already recorded in the database.
 * Returns an empty set when the migration table does not exist yet (fresh file).
 */
export function appliedIdentifiers(db) {
  const tableExists = db.exec(
    `SELECT 1 FROM sqlite_master WHERE type='table' AND name='${MIGRATION_TABLE}'`
  )
  if (!tableExists.length) return new Set()
  const rows = db.exec(`SELECT identifier FROM ${MIGRATION_TABLE}`)
  if (!rows.length) return new Set()
  return new Set(rows[0].values.map((r) => r[0]))
}

/**
 * True when the database carries migrations this build does not know about —
 * i.e. it was written by a newer peer. Mirrors GRDB's
 * `DatabaseMigrator.hasBeenSuperseded(_:)`.
 *
 * IMPORTANT: neither GRDB nor this module errors on unknown identifiers; both
 * proceed silently. Callers MUST check this and drop to read-only on true,
 * or a newer peer's columns will be written around and its invariants ignored.
 */
export function hasBeenSuperseded(db) {
  const known = new Set(KNOWN_IDENTIFIERS)
  for (const id of appliedIdentifiers(db)) {
    if (!known.has(id)) return true
  }
  return false
}

/** Identifiers present in the database but unknown here (for the read-only banner). */
export function unknownIdentifiers(db) {
  const known = new Set(KNOWN_IDENTIFIERS)
  return [...appliedIdentifiers(db)].filter((id) => !known.has(id))
}

/**
 * Applies every migration not yet recorded, in order, inside one transaction.
 * Safe on a fresh database and on a partially-migrated one.
 *
 * Does NOT guard against supersession — call `hasBeenSuperseded` first and
 * refuse to write if it returns true.
 *
 * @returns {string[]} identifiers applied by this call
 */
export function migrate(db) {
  db.run(`CREATE TABLE IF NOT EXISTS ${MIGRATION_TABLE} (identifier TEXT NOT NULL PRIMARY KEY)`)
  const applied = appliedIdentifiers(db)
  const pending = MIGRATIONS.filter((m) => !applied.has(m.identifier))
  if (!pending.length) return []

  // Foreign keys OFF during migration: v3/v10 rebuild tables via ALTER RENAME,
  // and SQLite re-checks FKs on those. GRDB does the same for its migrations.
  const fkRow = db.exec('PRAGMA foreign_keys')
  const fkWasOn = fkRow.length ? Boolean(fkRow[0].values[0][0]) : false
  if (fkWasOn) db.run('PRAGMA foreign_keys = OFF')

  try {
    db.run('BEGIN')
    for (const m of pending) {
      db.run(m.sql)
      const stmt = db.prepare(`INSERT INTO ${MIGRATION_TABLE} (identifier) VALUES (?)`)
      try { stmt.run([m.identifier]) } finally { stmt.free() }
    }
    db.run('COMMIT')
  } catch (err) {
    try { db.run('ROLLBACK') } catch { /* rollback of a failed BEGIN is not itself an error */ }
    throw err
  } finally {
    if (fkWasOn) db.run('PRAGMA foreign_keys = ON')
  }

  return pending.map((m) => m.identifier)
}
