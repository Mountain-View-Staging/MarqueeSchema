// GENERATED FILE — DO NOT EDIT.
// Source: MarqueeSchema/schema/migrations.json (+ schema/sql/*.sql)
// Regenerate: node tools/generate.mjs
// Checksum:   5ae651059b7200c19bbfe53f96472263dfd18d3c10c04d074e8480451cb16b7f

export const MIGRATION_TABLE = "grdb_migrations"
export const SCHEMA_CHECKSUM = "5ae651059b7200c19bbfe53f96472263dfd18d3c10c04d074e8480451cb16b7f"

/** Ordered, append-only. Index position is meaningful; never reorder. */
export const MIGRATIONS = Object.freeze([
    // Relational core: project / media_file / media_item / media_item_tag. Replaces the former blob-mirror `records` table.
    { identifier: "v1-relational", sql: "CREATE TABLE project (\n  id        INTEGER PRIMARY KEY AUTOINCREMENT,\n  cloud_uid TEXT    NOT NULL,\n  name      TEXT    NOT NULL,\n  created   INTEGER NOT NULL,\n  updated   INTEGER NOT NULL\n);\n\nCREATE TABLE media_file (\n  id                  INTEGER PRIMARY KEY AUTOINCREMENT,\n  file_name           TEXT    NOT NULL UNIQUE,\n  thumbnail_file_name TEXT,\n  content_type        TEXT    NOT NULL,\n  width               INTEGER,\n  height              INTEGER,\n  orientation         TEXT,\n  aspect_ratio        REAL,\n  intrinsic_duration  REAL,\n  file_size           INTEGER,\n  source_hash         TEXT,\n  content_hash        TEXT,\n  codec               TEXT,\n  color_space         TEXT,\n  was_converted       INTEGER NOT NULL DEFAULT 0,\n  original_type       TEXT,\n  original_file_name  TEXT,\n  source_document     TEXT,\n  source              TEXT,\n  created             INTEGER NOT NULL,\n  updated             INTEGER NOT NULL\n);\nCREATE UNIQUE INDEX idx_media_file_source_hash ON media_file (source_hash);\nCREATE INDEX idx_media_file_orientation ON media_file (orientation);\n\nCREATE TABLE media_item (\n  id                INTEGER PRIMARY KEY AUTOINCREMENT,\n  name              TEXT    NOT NULL,\n  portrait_file_id  INTEGER REFERENCES media_file(id) ON DELETE RESTRICT,\n  landscape_file_id INTEGER REFERENCES media_file(id) ON DELETE RESTRICT,\n  display_duration  REAL,\n  system_generated  INTEGER NOT NULL DEFAULT 0,\n  audio_priority    TEXT,\n  backing_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  overlay_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  archived          INTEGER NOT NULL DEFAULT 0,\n  created           INTEGER NOT NULL,\n  updated           INTEGER NOT NULL,\n  CHECK (portrait_file_id IS NOT NULL OR landscape_file_id IS NOT NULL)\n);\n\nCREATE TABLE media_item_tag (\n  item_id INTEGER NOT NULL REFERENCES media_item(id) ON DELETE CASCADE,\n  tag     TEXT    NOT NULL,\n  PRIMARY KEY (item_id, tag)\n);\n" },
    // Shared tag vocabulary + polymorphic cross-type assignment. Dissolves MediaSet: grouping = entities carrying a tag.
    { identifier: "v2-tags", sql: "DROP TABLE media_item_tag;\n\nCREATE TABLE tag (\n  id      INTEGER PRIMARY KEY AUTOINCREMENT,\n  name    TEXT    NOT NULL,\n  color   TEXT,\n  created INTEGER NOT NULL\n);\nCREATE UNIQUE INDEX idx_tag_name ON tag (name COLLATE NOCASE);\n\nCREATE TABLE tag_assignment (\n  tag_id      INTEGER NOT NULL REFERENCES tag(id) ON DELETE CASCADE,\n  entity_type TEXT    NOT NULL,\n  entity_id   INTEGER NOT NULL,\n  PRIMARY KEY (tag_id, entity_type, entity_id)\n);\nCREATE INDEX idx_tag_assignment_entity ON tag_assignment (entity_type, entity_id);\nCREATE INDEX idx_tag_assignment_tag    ON tag_assignment (tag_id, entity_type);\n" },
    // Split storage into write-once original + optional optimized copy. Deliverable = optimized ?? source.
    { identifier: "v3-source-optimized", sql: "ALTER TABLE media_file RENAME COLUMN file_name TO source_file_name;\nALTER TABLE media_file ADD COLUMN optimized_file_name TEXT;\nCREATE UNIQUE INDEX idx_media_file_optimized ON media_file (optimized_file_name);\n" },
    // Per-project default for optimize original-retention (keep vs consume).
    { identifier: "v4-retain-originals", sql: "ALTER TABLE project ADD COLUMN retain_originals INTEGER NOT NULL DEFAULT 1;\n" },
    // Playlists: ordered MediaItem instances + per-instance directives. The Playlist is the single directive authority.
    { identifier: "v5-playlists", sql: "CREATE TABLE playlist (\n  id                INTEGER PRIMARY KEY AUTOINCREMENT,\n  name              TEXT    NOT NULL,\n  shuffle           INTEGER NOT NULL DEFAULT 0,\n  is_seamless_video INTEGER NOT NULL DEFAULT 0,\n  backing_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  overlay_item_id   INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,\n  archived          INTEGER NOT NULL DEFAULT 0,\n  created           INTEGER NOT NULL,\n  updated           INTEGER NOT NULL\n);\n\nCREATE TABLE playlist_entry (\n  id            INTEGER PRIMARY KEY AUTOINCREMENT,\n  playlist_id   INTEGER NOT NULL REFERENCES playlist(id)   ON DELETE CASCADE,\n  media_item_id INTEGER NOT NULL REFERENCES media_item(id) ON DELETE RESTRICT,\n  position      INTEGER NOT NULL,\n  created       INTEGER NOT NULL,\n  updated       INTEGER NOT NULL\n);\nCREATE INDEX idx_playlist_entry_order ON playlist_entry (playlist_id, position);\nCREATE INDEX idx_playlist_entry_item  ON playlist_entry (media_item_id);\n\nCREATE TABLE directive (\n  id         INTEGER PRIMARY KEY AUTOINCREMENT,\n  entry_id   INTEGER NOT NULL REFERENCES playlist_entry(id) ON DELETE CASCADE,\n  type       TEXT    NOT NULL,   -- 'standard' | 'takeover'\n  timestamp  INTEGER NOT NULL,\n  on_screen  INTEGER NOT NULL,\n  timezone   TEXT,\n  created    INTEGER NOT NULL,\n  updated    INTEGER NOT NULL\n);\nCREATE INDEX idx_directive_entry ON directive (entry_id, timestamp);\n" },
    // Project timezone. (The former start_date/end_date range moved to project_days in v13; this migration was trimmed in place.)
    { identifier: "v6-project-schedule", sql: "ALTER TABLE project ADD COLUMN timezone TEXT;\n" },
    // Forward-declared open-vocabulary discriminator so the entry contract is stable. Today only 'media_item' resolves.
    { identifier: "v7-entry-resource-type", sql: "ALTER TABLE playlist_entry\n  ADD COLUMN resource_type TEXT NOT NULL DEFAULT 'media_item';\n" },
    // Per-instance playback windows in seconds of MEDIA time (clip offsets, not wall-clock), one pair per orientation.
    { identifier: "v8-entry-duration-override", sql: "ALTER TABLE playlist_entry ADD COLUMN start_time_portrait  REAL;\nALTER TABLE playlist_entry ADD COLUMN end_time_portrait    REAL;\nALTER TABLE playlist_entry ADD COLUMN start_time_landscape REAL;\nALTER TABLE playlist_entry ADD COLUMN end_time_landscape   REAL;\n" },
    // Screens: screen_config (scheduling unit) + screen_code (endpoints) + screen_schedule_entry (most-recent-<=-now-wins per slot).
    { identifier: "v9-screens", sql: "CREATE TABLE screen_config (\n  id        INTEGER PRIMARY KEY AUTOINCREMENT,\n  name      TEXT    NOT NULL,\n  revision  INTEGER NOT NULL DEFAULT 0,   -- monotonic; bumped on any schedule change\n  archived  INTEGER NOT NULL DEFAULT 0,\n  created   INTEGER NOT NULL,\n  updated   INTEGER NOT NULL\n);\n\nCREATE TABLE screen_code (\n  id                   INTEGER PRIMARY KEY AUTOINCREMENT,\n  config_id            INTEGER NOT NULL REFERENCES screen_config(id) ON DELETE CASCADE,\n  code                 TEXT    NOT NULL UNIQUE,   -- globally unique real-world id\n  orientation          TEXT    NOT NULL,          -- 'portrait' | 'landscape' (the mount)\n  label                TEXT,\n  last_checked_at      INTEGER,                   -- unix ms; \"is it online?\"\n  last_pulled_revision INTEGER,                   -- vs config.revision; \"needs update?\"\n  created              INTEGER NOT NULL,\n  updated              INTEGER NOT NULL\n);\nCREATE INDEX idx_screen_code_config ON screen_code (config_id);\n\nCREATE TABLE screen_schedule_entry (\n  id                 INTEGER PRIMARY KEY AUTOINCREMENT,\n  config_id          INTEGER NOT NULL REFERENCES screen_config(id) ON DELETE CASCADE,\n  slot               TEXT    NOT NULL,            -- 'portrait' | 'landscape' | 'demo_station'\n  timestamp          INTEGER NOT NULL,            -- most-recent <= now wins, per slot\n  playlist_id        INTEGER REFERENCES playlist(id)   ON DELETE RESTRICT,  -- portrait/landscape payload\n  background_item_id INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (behind)\n  overlay_item_id    INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (front)\n  created            INTEGER NOT NULL,\n  updated            INTEGER NOT NULL,\n  -- Playlist slots carry only a playlist; demo slots carry only branding,\n  -- and an overlay requires a background (background is required when branded;\n  -- both NULL = blank = exit demo mode).\n  CHECK (\n    ( slot IN ('portrait','landscape')\n        AND background_item_id IS NULL AND overlay_item_id IS NULL )\n    OR\n    ( slot = 'demo_station'\n        AND playlist_id IS NULL\n        AND ( background_item_id IS NOT NULL OR overlay_item_id IS NULL ) )\n  )\n);\nCREATE INDEX idx_screen_sched_slot ON screen_schedule_entry (config_id, slot, timestamp);\n" },
    // Cartridge-as-file identity: user-settable screen_id names the cartridge; screen_code becomes screen_location. Length/format/uniqueness are UI-enforced, not DB hard-stops.
    { identifier: "v10-screen-distribution", sql: "ALTER TABLE screen_config ADD COLUMN screen_id TEXT;\n\nALTER TABLE screen_config ADD COLUMN published_revision INTEGER;\nALTER TABLE screen_config ADD COLUMN published_at       INTEGER;\n\nALTER TABLE screen_code RENAME TO screen_location;\nALTER TABLE screen_location RENAME COLUMN code TO location_id;\n" },
    // ShowCode: short user-settable project addressing code. Consumers self-resolve <projectCode>/<screenCode>.db.
    { identifier: "v11-project-code", sql: "ALTER TABLE project ADD COLUMN project_code TEXT;\n" },
    // Project-level wallpaper pointers. ADD COLUMN with REFERENCES is legal because the NULL default satisfies SQLite's add-column FK rule.
    { identifier: "v12-project-wallpapers", sql: "ALTER TABLE project ADD COLUMN show_wallpaper_item_id INTEGER\n  REFERENCES media_item(id) ON DELETE RESTRICT;\n\nALTER TABLE project ADD COLUMN desktop_wallpaper_item_id INTEGER\n  REFERENCES media_item(id) ON DELETE RESTRICT;\n" },
    // Explicit non-contiguous schedule days, authored in the project timezone and stored verbatim as unix ms.
    { identifier: "v13-project-days", sql: "CREATE TABLE project_days (\n  id         INTEGER PRIMARY KEY AUTOINCREMENT,\n  day        TEXT    NOT NULL UNIQUE,\n  start_time INTEGER NOT NULL,\n  end_time   INTEGER NOT NULL,\n  created    INTEGER NOT NULL,\n  updated    INTEGER NOT NULL\n);\nCREATE INDEX idx_project_day_start ON project_days (start_time);\n" },
    // Marks whether a show requires an enable-edit code. A FLAG ONLY — the verifier lives server-side in KV, never in the database. The authoring DB is publicly downloadable and the project row is copied verbatim into every published cartridge, so a hash stored here would be offline-crackable and shipped to every venue device.
    { identifier: "v14-project-edit-gate", sql: "ALTER TABLE project ADD COLUMN edit_code_required INTEGER NOT NULL DEFAULT 0;\n" },
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
