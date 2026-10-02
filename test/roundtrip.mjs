/*
******************************************************

  roundtrip.mjs
  @copyright 2026 Dustin Nielson

  The file-compatibility proof.

  Phase A — JS authors a project from scratch with sql.js and the
            generated migrations; Swift/GRDB opens it, applies NOTHING,
            and decodes every record type.
  Phase B — Swift authors a project; JS opens it, mutates it (media
            files, items, a playlist with entries and a directive, a
            surface with a location and a schedule entry, tags, project
            days), exports; Swift reopens and sees exactly those changes.

  Passing both means the two implementations can hand the same file back
  and forth without either losing or corrupting the other's work.

    node --no-warnings test/roundtrip.mjs

******************************************************
*/
import initSqlJs from 'sql.js'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync, readFileSync, mkdirSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { migrate, hasBeenSuperseded, unknownIdentifiers, KNOWN_IDENTIFIERS, MIGRATIONS, MIGRATION_TABLE } from '../dist/migrations.js'

const REFGEN = new URL('../tools/swift-reference/.build/debug/refgen', import.meta.url).pathname

if (!existsSync(REFGEN)) {
  console.error('refgen not built. Run:  cd tools/swift-reference && swift build')
  process.exit(2)
}

const SQL = await initSqlJs()
const work = mkdtempSync(join(tmpdir(), 'marquee-roundtrip-'))
const failures = []
let checks = 0

function check(label, condition, detail = '') {
  checks++
  if (condition) {
    console.log(`  ✓ ${label}`)
  } else {
    console.log(`  ✗ ${label}${detail ? ` — ${detail}` : ''}`)
    failures.push(label)
  }
}

/** Runs Swift's inspector over a database and returns its JSON summary. */
function swiftInspect(dbPath) {
  try {
    return JSON.parse(execFileSync(REFGEN, ['inspect', dbPath], { encoding: 'utf8' }))
  } catch (err) {
    const stderr = (err.stderr || '').toString().trim()
    throw new Error(`GRDB could not open the database: ${stderr || err.message}`)
  }
}

function swiftCreate(dbPath) {
  execFileSync(REFGEN, ['create', dbPath], { encoding: 'utf8' })
}

/**
 * Writes a sql.js database to a `.proj`-shaped bundle, since Swift's
 * MediaService resolves Media/ relative to Database/Marquee.db.
 */
function writeProject(name, db) {
  const root = join(work, `${name}.proj`)
  mkdirSync(join(root, 'Database'), { recursive: true })
  mkdirSync(join(root, 'Media', 'Originals'), { recursive: true })
  const dbPath = join(root, 'Database', 'Marquee.db')
  writeFileSync(dbPath, Buffer.from(db.export()))
  return dbPath
}

const NOW = 1_784_000_000_000

// ── Phase A — JS authors, Swift reads ──────────────────────────────────────
console.log('\nPhase A — JS authors a project from scratch, Swift opens it')

const fresh = new SQL.Database()
const applied = migrate(fresh)
check(`applied all ${KNOWN_IDENTIFIERS.length} migrations`, applied.length === KNOWN_IDENTIFIERS.length,
  `applied ${applied.length}`)
check('a second migrate() is a no-op', migrate(fresh).length === 0)
check('not superseded by itself', hasBeenSuperseded(fresh) === false)

// v16-retire-style-book: a v15 show carrying a style book. The book's own items (its
// style.json and a face, members; a set's book named only by pointer) are archived; a
// brand logo — an image, also a member — stays; the columns and the index are gone.
{
  const v15 = new SQL.Database()
  v15.run(`CREATE TABLE ${MIGRATION_TABLE} (identifier TEXT NOT NULL PRIMARY KEY)`)
  for (const m of MIGRATIONS.slice(0, MIGRATIONS.findIndex((m) => m.identifier === 'v16-retire-style-book'))) {
    v15.run(m.sql)
    v15.run(`INSERT INTO ${MIGRATION_TABLE} (identifier) VALUES (?)`, [m.identifier])
  }
  const files = [['style.json', 'application/json'], ['face.woff2', 'font/woff2'], ['logo.png', 'image/png'],
                 ['set-style.json', 'application/json'], ['content.png', 'image/png']]
  files.forEach(([name, type], i) => v15.run(
    `INSERT INTO media_file (id, source_file_name, content_type, created, updated) VALUES (?, ?, ?, ?, ?)`,
    [i + 1, name, type, NOW, NOW]))
  const book = 'acme/acme-2026/3'
  for (const [id, member] of [[1, book], [2, book], [3, book], [4, null], [5, null]]) {
    v15.run(`INSERT INTO media_item (id, name, landscape_file_id, brand_member, created, updated) VALUES (?, ?, ?, ?, ?, ?)`,
      [id, files[id - 1][0], id, member, NOW, NOW])
  }
  v15.run(`INSERT INTO project (cloud_uid, name, brand_style, brand_style_item_id, created, updated) VALUES ('u', 'Show', ?, 1, ?, ?)`, [book, NOW, NOW])
  v15.run(`INSERT INTO session_set (name, brand_style, brand_style_item_id, created, updated) VALUES ('Room', 'acme/room/1', 4, ?, ?)`, [NOW, NOW])
  check('v16 is the one migration a v15 show takes', JSON.stringify(migrate(v15)) === '["v16-retire-style-book"]')
  const archived = v15.exec('SELECT id FROM media_item WHERE archived = 1 ORDER BY id')[0]?.values.flat() ?? []
  check('v16 archives the style book\'s own items (style.json, a face, a set\'s book), not a brand logo or content',
    JSON.stringify(archived) === '[1,2,4]', JSON.stringify(archived))
  const cols = (t) => v15.exec(`PRAGMA table_info(${t})`)[0].values.map((r) => r[1])
  check('v16 drops the style book columns',
    !cols('project').some((c) => c.startsWith('brand_')) && !cols('session_set').some((c) => c.startsWith('brand_')) &&
    !cols('media_item').includes('brand_member'))
  check('v16 drops the brand_member index',
    v15.exec(`SELECT 1 FROM sqlite_master WHERE name = 'idx_media_item_brand_member'`).length === 0)
  check('v16 leaves the database consistent', v15.exec('PRAGMA foreign_key_check').length === 0)
}

fresh.run(
  `INSERT INTO project (cloud_uid, name, created, updated, retain_originals, timezone, project_code)
   VALUES ('11111111-2222-3333-4444-555555555555', 'JS Authored', ?, ?, 1, 'America/Los_Angeles', 'CNX2026')`,
  [NOW, NOW]
)

const phaseA = writeProject('JSAuthored', fresh)
let a
try {
  a = swiftInspect(phaseA)
  check('GRDB opened the JS-authored database', true)
} catch (err) {
  check('GRDB opened the JS-authored database', false, err.message)
}

if (a) {
  check('GRDB ran NO migrations on open', a.migrationsRunOnOpen.length === 0,
    `ran ${JSON.stringify(a.migrationsRunOnOpen)}`)
  check('migration identifiers match, in order',
    a.migrationsApplied.join(',') === KNOWN_IDENTIFIERS.join(','))
  check('project decoded', a.projectName === 'JS Authored', `got ${a.projectName}`)
  check('project_code decoded', a.projectCode === 'CNX2026', `got ${a.projectCode}`)
  check('timezone decoded', a.timezone === 'America/Los_Angeles', `got ${a.timezone}`)
}
fresh.close()

// ── Phase B — Swift authors, JS mutates, Swift re-reads ────────────────────
console.log('\nPhase B — Swift authors, JS mutates, Swift re-reads')

const swiftRoot = join(work, 'SwiftAuthored.proj')
mkdirSync(join(swiftRoot, 'Database'), { recursive: true })
mkdirSync(join(swiftRoot, 'Media', 'Originals'), { recursive: true })
const swiftDbPath = join(swiftRoot, 'Database', 'Marquee.db')
swiftCreate(swiftDbPath)
// GRDB opens WAL; collapse the sidecars so the file is self-contained, exactly
// as the desktop must before any cloud push (Architecture §2.3 R3).
execFileSync('sqlite3', [swiftDbPath, 'PRAGMA wal_checkpoint(TRUNCATE);'])

const loaded = new SQL.Database(new Uint8Array(readFileSync(swiftDbPath)))
check('JS opened the Swift-authored database', true)
check('no unknown migrations', hasBeenSuperseded(loaded) === false,
  JSON.stringify(unknownIdentifiers(loaded)))
check('JS runs no migrations on a current file', migrate(loaded).length === 0)

// Foreign keys ON — the delete guards depend on it, and it proves the JS writes
// satisfy every FK the schema declares.
loaded.run('PRAGMA foreign_keys = ON')

const uuidLandscape = '7a1c0e64-9d3b-4a52-b0f1-2c8e5d6a9b31'
const uuidPortrait = 'c4e8b920-1f6a-4d73-9e05-8b2a7c1d4f60'

loaded.run(
  `INSERT INTO media_file (source_file_name, thumbnail_file_name, content_type, width, height,
                           orientation, aspect_ratio, file_size, source_hash, content_hash,
                           was_converted, original_file_name, source, created, updated)
   VALUES (?, ?, 'image/png', 1920, 1080, 'landscape', 1.7777777777777777, 437911,
           'sha256:74a79df4fafdec06ae75a0a316626bbf88163a2d8511cf1f8783c5d365e892f6',
           'sha256:74a79df4fafdec06ae75a0a316626bbf88163a2d8511cf1f8783c5d365e892f6',
           0, 'hero_landscape.png', 'files', ?, ?)`,
  [`${uuidLandscape}.png`, `${uuidLandscape}_thumb.png`, NOW, NOW]
)
loaded.run(
  `INSERT INTO media_file (source_file_name, thumbnail_file_name, content_type, width, height,
                           orientation, aspect_ratio, file_size, source_hash, content_hash,
                           was_converted, original_file_name, source, created, updated)
   VALUES (?, ?, 'image/png', 1080, 1920, 'portrait', 0.5625, 551314,
           'sha256:7aed25203443f997dd4d85aed3184bc2663acc7ffd33285d0dd9696043db33b1',
           'sha256:7aed25203443f997dd4d85aed3184bc2663acc7ffd33285d0dd9696043db33b1',
           0, 'hero_portrait.png', 'files', ?, ?)`,
  [`${uuidPortrait}.png`, `${uuidPortrait}_thumb.png`, NOW, NOW]
)

loaded.run(
  `INSERT INTO media_item (name, portrait_file_id, landscape_file_id, display_duration,
                           system_generated, archived, created, updated)
   VALUES ('Hero Slide', 2, 1, 8.0, 0, 0, ?, ?)`,
  [NOW, NOW]
)
loaded.run(
  `INSERT INTO media_item (name, landscape_file_id, system_generated, archived, created, updated)
   VALUES ('Sponsor Loop', 1, 0, 0, ?, ?)`,
  [NOW, NOW]
)

loaded.run(
  `INSERT INTO playlist (name, is_seamless_video, archived, created, updated)
   VALUES ('Lobby Loop', 0, 0, ?, ?)`,
  [NOW, NOW]
)
loaded.run(
  `INSERT INTO playlist_entry (playlist_id, media_item_id, position, resource_type,
                               start_time_landscape, end_time_landscape, created, updated)
   VALUES (1, 1, 0, 'media_item', 0.0, 6.5, ?, ?)`,
  [NOW, NOW]
)
loaded.run(
  `INSERT INTO playlist_entry (playlist_id, media_item_id, position, resource_type, created, updated)
   VALUES (1, 2, 1, 'media_item', ?, ?)`,
  [NOW, NOW]
)
loaded.run(
  `INSERT INTO directive (entry_id, type, timestamp, on_screen, timezone, created, updated)
   VALUES (1, 'takeover', ?, 1, 'America/Los_Angeles', ?, ?)`,
  [NOW + 3_600_000, NOW, NOW]
)

loaded.run(
  `INSERT INTO surface_config (name, revision, archived, surface_id, created, updated)
   VALUES ('Lobby', 1, 0, 'LBY', ?, ?)`,
  [NOW, NOW]
)
loaded.run(
  `INSERT INTO surface_location (config_id, location_id, label, created, updated)
   VALUES (1, 'LOBBY-01', 'North wall', ?, ?)`,
  [NOW, NOW]
)
loaded.run(
  `INSERT INTO surface_schedule_entry (config_id, slot, timestamp, playlist_id, created, updated)
   VALUES (1, 'playlist', ?, 1, ?, ?)`,
  [NOW, NOW, NOW]
)

loaded.run(`INSERT INTO tag (name, color, created) VALUES ('sponsor', '#D7BA7D', ?)`, [NOW])
loaded.run(`INSERT INTO tag_assignment (tag_id, entity_type, entity_id) VALUES (1, 'media_item', 2)`)

loaded.run(
  `INSERT INTO project_days (day, start_time, end_time, created, updated)
   VALUES ('2026-09-14', ?, ?, ?, ?)`,
  [NOW, NOW + 86_399_000, NOW, NOW]
)

loaded.run(`UPDATE project SET project_code = 'CNX2026', timezone = 'America/Los_Angeles', updated = ?`, [NOW])

// v13: the project's arrays — emergency screens (inserted out of order, read back by
// position), a switch on the first, and links.
loaded.run(`INSERT INTO emergency_screen (name, media_item_id, position, created, updated) VALUES ('Shelter', 2, 1, ?, ?)`, [NOW, NOW])
loaded.run(`INSERT INTO emergency_screen (name, media_item_id, position, created, updated) VALUES ('Evacuate', 1, 0, ?, ?)`, [NOW, NOW])
loaded.run(`INSERT INTO emergency_screen_directive (emergency_screen_id, timestamp, on_screen, timezone, created, updated)
            VALUES (2, ?, 1, 'America/Los_Angeles', ?, ?)`, [NOW, NOW, NOW])
loaded.run(`INSERT INTO project_link (name, uri, position, created, updated) VALUES ('Run of show', 'https://docs.example/ros', 0, ?, ?)`, [NOW, NOW])
loaded.run(`INSERT INTO project_link (name, uri, position, created, updated) VALUES ('Venue files', 'https://drive.example/f', 1, ?, ?)`, [NOW, NOW])

// v12's CHECK (the wire's): one schedule per surface — a retired per-orientation slot
// is refused, and a demo entry is branding only, never a playlist (D-r2-30).
for (const [label, values] of [
  ["a retired 'portrait' slot", `(1, 'portrait', ${NOW}, 1, NULL, ${NOW}, ${NOW})`],
  ["a retired 'landscape' slot", `(1, 'landscape', ${NOW}, 1, NULL, ${NOW}, ${NOW})`],
  ['a demo entry with a playlist', `(1, 'demo_station', ${NOW}, 1, 1, ${NOW}, ${NOW})`],
]) {
  let refused = false
  try {
    loaded.run(`INSERT INTO surface_schedule_entry (config_id, slot, timestamp, playlist_id, background_item_id, created, updated)
                VALUES ${values}`)
  } catch { refused = true }
  check(`surface_schedule_entry CHECK refuses ${label}`, refused)
}

// Exercise the CHECK constraint that guarantees "an item always keeps >= 1 file".
let checkRejected = false
try {
  loaded.run(`INSERT INTO media_item (name, system_generated, archived, created, updated)
              VALUES ('Empty', 0, 0, ?, ?)`, [NOW, NOW])
} catch { checkRejected = true }
check('media_item CHECK rejects an item with no files', checkRejected)

// Exercise FK RESTRICT — a referenced file must not be deletable.
let fkRestricted = false
try {
  loaded.run('DELETE FROM media_file WHERE id = 1')
} catch { fkRestricted = true }
check('FK RESTRICT blocks deleting a referenced media_file', fkRestricted)

const phaseB = writeProject('SwiftAuthoredMutated', loaded)
loaded.close()

let b
try {
  b = swiftInspect(phaseB)
  check('GRDB reopened the JS-mutated database', true)
} catch (err) {
  check('GRDB reopened the JS-mutated database', false, err.message)
}

if (b) {
  check('GRDB ran NO migrations on reopen', b.migrationsRunOnOpen.length === 0,
    `ran ${JSON.stringify(b.migrationsRunOnOpen)}`)
  check('2 media files decoded', b.mediaFiles === 2, `got ${b.mediaFiles}`)
  check('media file names round-tripped',
    b.mediaFileNames.join(',') === [`${uuidLandscape}.png`, `${uuidPortrait}.png`].sort().join(','),
    JSON.stringify(b.mediaFileNames))
  check('2 media items decoded', b.mediaItems === 2, `got ${b.mediaItems}`)
  check('media item names round-tripped',
    b.mediaItemNames.join(',') === 'Hero Slide,Sponsor Loop', JSON.stringify(b.mediaItemNames))
  check('1 playlist decoded', b.playlists === 1, `got ${b.playlists}`)
  check('2 playlist entries decoded', b.playlistEntries === 2, `got ${b.playlistEntries}`)
  check('1 directive decoded', b.directives === 1, `got ${b.directives}`)
  check('1 surface config decoded', b.surfaceConfigs === 1, `got ${b.surfaceConfigs}`)
  check('1 surface location decoded', b.surfaceLocations === 1, `got ${b.surfaceLocations}`)
  check('1 schedule entry decoded', b.scheduleEntries === 1, `got ${b.scheduleEntries}`)
  check('1 tag decoded', b.tags === 1, `got ${b.tags}`)
  check('1 project day decoded', b.projectDays === 1, `got ${b.projectDays}`)
  check('project edits persisted', b.projectCode === 'CNX2026', `got ${b.projectCode}`)
  check('2 emergency screens decoded, in the array\'s order',
    b.emergencyScreens === 2 && b.emergencyScreenNames.join(',') === 'Evacuate,Shelter', JSON.stringify(b.emergencyScreenNames))
  check('1 emergency screen directive decoded', b.emergencyScreenDirectives === 1, `got ${b.emergencyScreenDirectives}`)
  check('2 project links decoded, in the array\'s order',
    b.projectLinks === 2 && b.projectLinkURIs.join(',') === 'https://docs.example/ros,https://drive.example/f', JSON.stringify(b.projectLinkURIs))
}

// ── Supersession guard ─────────────────────────────────────────────────────
console.log('\nSupersession guard — a newer peer writes a migration we do not know')

const future = new SQL.Database()
migrate(future)
future.run(`INSERT INTO grdb_migrations (identifier) VALUES ('v99-from-the-future')`)
check('hasBeenSuperseded detects the unknown identifier', hasBeenSuperseded(future) === true)
check('unknownIdentifiers names it',
  unknownIdentifiers(future).join(',') === 'v99-from-the-future',
  JSON.stringify(unknownIdentifiers(future)))
future.close()

rmSync(work, { recursive: true, force: true })

console.log(`\n${checks - failures.length}/${checks} checks passed`)
if (failures.length) {
  console.log('FAILED:')
  for (const f of failures) console.log(`  - ${f}`)
  process.exit(1)
}
console.log('PASS — files round-trip between sql.js and GRDB without loss')
