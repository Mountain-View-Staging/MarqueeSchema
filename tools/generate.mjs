/*
******************************************************

  generate.mjs
  @copyright 2026 Dustin Nielson

  Generates the per-platform migration modules from the
  source of truth in schema/.

    node tools/generate.mjs           # write dist/
    node tools/generate.mjs --check   # fail if dist/ is stale (CI)

******************************************************
*/
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { join, dirname, basename } from 'node:path'
import { loadMigrations, DIST_DIR, REPO_ROOT } from './loader.mjs'

const CHECK_ONLY = process.argv.includes('--check')

// The generated Swift migrator is ALSO written straight into MarqueeDataKit,
// which adopts it directly (`MarqueeStore.migrator == MarqueeSchema.migrator`),
// so the desktop can never drift from the shared schema. Sibling checkout via
// the same relative path the Swift reference tool already assumes; skipped
// gracefully when absent so a schema-only checkout still generates dist/.
const DATAKIT_SWIFT = join(
  REPO_ROOT, '..', 'SPM', 'MarqueeDataKit', 'Sources', 'MarqueeDataKit', 'MarqueeSchema.swift'
)

const banner = (checksum) => `// GENERATED FILE — DO NOT EDIT.
// Source: MarqueeSchema/schema/migrations.json (+ schema/sql/*.sql)
// Regenerate: node tools/generate.mjs
// Checksum:   ${checksum}
`

/** ESM module for MarqueeStudioWeb (sql.js). */
function renderJavaScript({ migrations, migrationTable, checksum }) {
  const entries = migrations.map((m) => {
    const note = m.note ? `    // ${m.note}\n` : ''
    return `${note}    { identifier: ${JSON.stringify(m.identifier)}, sql: ${JSON.stringify(m.sql)} },`
  }).join('\n')

  return `${banner(checksum)}
export const MIGRATION_TABLE = ${JSON.stringify(migrationTable)}
export const SCHEMA_CHECKSUM = ${JSON.stringify(checksum)}

/** Ordered, append-only. Index position is meaningful; never reorder. */
export const MIGRATIONS = Object.freeze([
${entries}
].map(Object.freeze))

export const KNOWN_IDENTIFIERS = Object.freeze(MIGRATIONS.map((m) => m.identifier))

/**
 * Identifiers already recorded in the database.
 * Returns an empty set when the migration table does not exist yet (fresh file).
 */
export function appliedIdentifiers(db) {
  const tableExists = db.exec(
    \`SELECT 1 FROM sqlite_master WHERE type='table' AND name='\${MIGRATION_TABLE}'\`
  )
  if (!tableExists.length) return new Set()
  const rows = db.exec(\`SELECT identifier FROM \${MIGRATION_TABLE}\`)
  if (!rows.length) return new Set()
  return new Set(rows[0].values.map((r) => r[0]))
}

/**
 * True when the database carries migrations this build does not know about —
 * i.e. it was written by a newer peer. Mirrors GRDB's
 * \`DatabaseMigrator.hasBeenSuperseded(_:)\`.
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
 * Does NOT guard against supersession — call \`hasBeenSuperseded\` first and
 * refuse to write if it returns true.
 *
 * @returns {string[]} identifiers applied by this call
 */
export function migrate(db) {
  db.run(\`CREATE TABLE IF NOT EXISTS \${MIGRATION_TABLE} (identifier TEXT NOT NULL PRIMARY KEY)\`)
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
      const stmt = db.prepare(\`INSERT INTO \${MIGRATION_TABLE} (identifier) VALUES (?)\`)
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
`
}

/** Swift module for MarqueeDataKit (GRDB). */
function renderSwift({ migrations, checksum }) {
  const cases = migrations.map((m) => {
    const note = m.note ? `        // ${m.note}\n` : ''
    // Swift raw strings: #"""..."""# tolerates any quoting/backslashes in the SQL.
    return `${note}        migrator.registerMigration(${JSON.stringify(m.identifier)}) { db in
            try db.execute(sql: #"""
${m.sql.trimEnd()}
"""#)
        }`
  }).join('\n')

  return `${banner(checksum)}
import Foundation
import GRDB

/// The Marquee schema, generated from the shared \`MarqueeSchema\` repo.
///
/// Do not add migrations here — add them to \`schema/migrations.json\` in that
/// repo and regenerate, so the Swift and JavaScript peers stay identical. The
/// identifiers below are written verbatim into \`grdb_migrations\` and compared
/// character-for-character across implementations.
public enum MarqueeSchema {

    /// sha256 over every identifier + SQL body. Compare across peers to detect drift.
    public static let checksum = ${JSON.stringify(checksum)}

    /// Ordered, append-only.
    public static let knownIdentifiers: [String] = [
${migrations.map((m) => `        ${JSON.stringify(m.identifier)},`).join('\n')}
    ]

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
${cases}
        return migrator
    }
}
`
}

function emit(path, contents, { optional = false } = {}) {
  const label = path.startsWith(DIST_DIR) ? `dist/${basename(path)}` : path
  const dir = dirname(path)
  // An optional target whose directory is not present (sibling repo not checked
  // out) is not an error — dist/ is always generated; the copy is best-effort.
  if (optional && !existsSync(dir)) {
    console.log(`• skipped ${label} (target not present)`)
    return true
  }
  if (CHECK_ONLY) {
    let existing
    try {
      existing = readFileSync(path, 'utf8')
    } catch {
      console.error(`✗ ${label} is missing. Run: node tools/generate.mjs`)
      return false
    }
    if (existing !== contents) {
      console.error(`✗ ${label} is stale. Run: node tools/generate.mjs`)
      return false
    }
    console.log(`✓ ${label} up to date`)
    return true
  }
  mkdirSync(dir, { recursive: true })
  writeFileSync(path, contents)
  console.log(`wrote ${label}`)
  return true
}

let schema
try {
  schema = loadMigrations()
} catch (err) {
  console.error(`✗ schema/ is invalid: ${err.message}`)
  process.exit(2)
}

const swift = renderSwift(schema)
const results = [
  emit(join(DIST_DIR, 'migrations.js'), renderJavaScript(schema)),
  emit(join(DIST_DIR, 'MarqueeSchema.swift'), swift),
  emit(DATAKIT_SWIFT, swift, { optional: true }),
]

console.log(`${schema.migrations.length} migrations · checksum ${schema.checksum.slice(0, 16)}…`)

if (!results.every(Boolean)) process.exit(1)
