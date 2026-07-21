/*
******************************************************

  verify.mjs
  @copyright 2026 Dustin Nielson

  Proves that a database built from schema/ is structurally
  identical to one built by the Swift/GRDB implementation.

    node tools/verify.mjs                      # against test/fixtures/reference.db
    node tools/verify.mjs "/path/My Show.proj/Database/Marquee.db"

  Compares SEMANTICS, not stored DDL text: tables, columns
  (type/notnull/default/pk), indexes (uniqueness + column order),
  and foreign keys (target/on-delete). Raw sqlite_master text is
  deliberately NOT compared — SQLite stores CREATE statements
  verbatim, so comment and whitespace differences between the two
  implementations would produce noise that means nothing.

******************************************************
*/
import { DatabaseSync } from 'node:sqlite'
import { mkdtempSync, rmSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { loadMigrations, splitStatements } from './loader.mjs'

const MIGRATION_TABLE = 'grdb_migrations'

/** Builds a fresh database by applying every migration in order. */
function buildFromSource(path, migrations) {
  const db = new DatabaseSync(path)
  db.exec('PRAGMA foreign_keys = OFF')
  db.exec(`CREATE TABLE IF NOT EXISTS ${MIGRATION_TABLE} (identifier TEXT NOT NULL PRIMARY KEY)`)
  db.exec('BEGIN')
  for (const m of migrations) {
    for (const statement of splitStatements(m.sql)) db.exec(statement)
    db.prepare(`INSERT INTO ${MIGRATION_TABLE} (identifier) VALUES (?)`).run(m.identifier)
  }
  db.exec('COMMIT')
  return db
}

/** Structural fingerprint of a database: everything that affects compatibility. */
function introspect(db) {
  const tables = db
    .prepare(
      `SELECT name FROM sqlite_master
        WHERE type='table' AND name NOT LIKE 'sqlite_%'
        ORDER BY name`
    )
    .all()
    .map((r) => r.name)

  const shape = {}
  for (const table of tables) {
    const columns = db.prepare(`PRAGMA table_info(${table})`).all().map((c) => ({
      name: c.name,
      type: c.type,
      notnull: c.notnull,
      default: c.dflt_value,
      pk: c.pk,
    }))

    const foreignKeys = db.prepare(`PRAGMA foreign_key_list(${table})`).all()
      .map((f) => `${f.from} -> ${f.table}.${f.to} ON DELETE ${f.on_delete}`)
      .sort()

    const indexes = db.prepare(`PRAGMA index_list(${table})`).all()
      .filter((i) => !i.name.startsWith('sqlite_autoindex_'))
      .map((i) => {
        const cols = db.prepare(`PRAGMA index_info(${i.name})`).all().map((c) => c.name)
        return `${i.name}${i.unique ? ' UNIQUE' : ''} (${cols.join(', ')})`
      })
      .sort()

    // Implicit indexes from UNIQUE/PRIMARY KEY constraints are named
    // sqlite_autoindex_* and are unstable across statement rewrites; the
    // constraint itself shows up in the column/DDL shape instead.
    shape[table] = { columns, indexes, foreignKeys }
  }
  return shape
}

function diff(expected, actual, labelExpected, labelActual) {
  const problems = []
  const names = [...new Set([...Object.keys(expected), ...Object.keys(actual)])].sort()

  for (const table of names) {
    if (!actual[table]) { problems.push(`table "${table}" missing from ${labelActual}`); continue }
    if (!expected[table]) { problems.push(`table "${table}" missing from ${labelExpected}`); continue }

    const e = expected[table]
    const a = actual[table]

    const eCols = new Map(e.columns.map((c) => [c.name, c]))
    const aCols = new Map(a.columns.map((c) => [c.name, c]))
    for (const name of new Set([...eCols.keys(), ...aCols.keys()])) {
      const ec = eCols.get(name)
      const ac = aCols.get(name)
      if (!ac) { problems.push(`${table}.${name} missing from ${labelActual}`); continue }
      if (!ec) { problems.push(`${table}.${name} missing from ${labelExpected}`); continue }
      for (const key of ['type', 'notnull', 'default', 'pk']) {
        if (String(ec[key]) !== String(ac[key])) {
          problems.push(`${table}.${name} ${key}: ${labelExpected}=${ec[key]} ${labelActual}=${ac[key]}`)
        }
      }
    }

    // Column ORDER matters: SELECT * and positional binding depend on it.
    const eOrder = e.columns.map((c) => c.name).join(',')
    const aOrder = a.columns.map((c) => c.name).join(',')
    if (eOrder !== aOrder) {
      problems.push(`${table} column order differs\n    ${labelExpected}: ${eOrder}\n    ${labelActual}: ${aOrder}`)
    }

    for (const [kind, key] of [['index', 'indexes'], ['foreign key', 'foreignKeys']]) {
      for (const item of e[key]) if (!a[key].includes(item)) problems.push(`${table} ${kind} missing from ${labelActual}: ${item}`)
      for (const item of a[key]) if (!e[key].includes(item)) problems.push(`${table} ${kind} unexpected in ${labelActual}: ${item}`)
    }
  }
  return problems
}

// ── run ────────────────────────────────────────────────────────────────────

let migrations
try {
  ;({ migrations } = loadMigrations())
} catch (err) {
  console.error(`✗ schema/ is invalid: ${err.message}`)
  process.exit(2)
}

const reference = process.argv[2] || new URL('../test/fixtures/reference.db', import.meta.url).pathname

if (!existsSync(reference)) {
  console.error(`Reference database not found: ${reference}`)
  console.error('Pass one explicitly:  node tools/verify.mjs "/path/My Show.proj/Database/Marquee.db"')
  process.exit(2)
}

const workDir = mkdtempSync(join(tmpdir(), 'marquee-schema-'))
let failed = false

try {
  const generated = buildFromSource(join(workDir, 'generated.db'), migrations)
  const referenceDb = new DatabaseSync(reference, { readOnly: true })

  // 1. Migration identifiers must match exactly, in order.
  const expectedIds = referenceDb.prepare(`SELECT identifier FROM ${MIGRATION_TABLE}`).all().map((r) => r.identifier)
  const actualIds = generated.prepare(`SELECT identifier FROM ${MIGRATION_TABLE}`).all().map((r) => r.identifier)
  if (expectedIds.join('\n') !== actualIds.join('\n')) {
    console.error('✗ grdb_migrations differs')
    console.error(`  reference: ${expectedIds.join(', ')}`)
    console.error(`  generated: ${actualIds.join(', ')}`)
    failed = true
  } else {
    console.log(`✓ grdb_migrations — ${actualIds.length} identifiers match`)
  }

  // 2. Structure must match.
  const problems = diff(introspect(referenceDb), introspect(generated), 'reference', 'generated')
  if (problems.length) {
    console.error(`✗ ${problems.length} structural difference(s):`)
    for (const p of problems) console.error(`  - ${p}`)
    failed = true
  } else {
    console.log(`✓ structure — tables, columns, indexes, and foreign keys match`)
  }

  referenceDb.close()
  generated.close()
} finally {
  rmSync(workDir, { recursive: true, force: true })
}

console.log(failed ? '\nFAILED' : `\nPASS — schema/ reproduces ${reference}`)
process.exit(failed ? 1 : 0)
