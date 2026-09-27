/*
  verify-web.mjs — the web Studio's half of the checks, over the generated shows.

    node --no-warnings tools/test-shows/verify-web.mjs <marquee-test-shows checkout>

  For each show: its `_studio/Marquee.db` opens through MarqueeStudioWeb's data layer
  (`MarqueeProject.open`, sql.js + the pinned marquee-schema migrator) writable and not
  superseded, with nothing to migrate; the facade reads the library; and for every
  published surface the web's writer (`cartridge.surfaceCartridgeRows`, at the cartridge's
  own generated_at) produces the same rows as the kit wrote into `<SURFACE>.db`, table for
  table — the one expected difference being `surface_config.updated`, which the kit's
  markPublished moved after the file was written.

  Needs the sibling checkout ../../../MarqueeStudio/MarqueeStudioWeb with its node_modules.
*/
import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { DatabaseSync } from 'node:sqlite'

const repo = resolve(process.argv[2] ?? '')
if (!existsSync(join(repo, 'shows'))) {
  console.error('usage: node verify-web.mjs <marquee-test-shows checkout>')
  process.exit(2)
}
const web = new URL('../../../MarqueeStudio/MarqueeStudioWeb/', import.meta.url)
const { MarqueeProject } = await import(new URL('src/db/index.js', web))
const cartridge = await import(new URL('src/db/cartridge.js', web))
const { KNOWN_IDENTIFIERS } = await import(new URL('node_modules/marquee-schema/dist/migrations.js', web))

let failures = 0
const fail = (what) => { failures++; console.log(`  ✗ ${what}`) }

for (const code of readdirSync(join(repo, 'shows')).filter((n) => !n.startsWith('.')).sort()) {
  const root = join(repo, 'shows', code)
  const bytes = readFileSync(join(root, '_studio/Marquee.db'))
  const project = await MarqueeProject.open(bytes)
  const db = project.db
  const ids = db.all('SELECT identifier FROM grdb_migrations ORDER BY rowid').map((r) => r.identifier)
  if (project.isReadOnly) fail(`${code}: opens read-only (superseded by ${project.supersededBy.join(', ')})`)
  if (JSON.stringify(ids) !== JSON.stringify(KNOWN_IDENTIFIERS)) fail(`${code}: identifiers ${ids.at(-1)} vs the web's ${KNOWN_IDENTIFIERS.at(-1)}`)
  const row = project.loadProject()
  const library = project.loadMediaLibrary({ includeArchived: true })
  const items = project.loadMediaItems({ includeArchived: true })
  const count = (sql) => Number(db.value(sql))
  console.log(`${code} — the web data layer: ${row.name}, ${row.timezone}, at ${ids.at(-1)}, writable; `
    + `${library.files.length} media files, ${items.length} items, `
    + `${count('SELECT COUNT(*) FROM playlist')} playlists, ${count('SELECT COUNT(*) FROM playlist_entry')} entries, `
    + `${count('SELECT COUNT(*) FROM directive')} directives, ${count('SELECT COUNT(*) FROM surface_config')} surface configs`)

  // The web writer against the kit's cartridges, surface by surface.
  for (const config of db.all('SELECT id, surface_id FROM surface_config WHERE surface_id IS NOT NULL ORDER BY id')) {
    const file = join(root, `${config.surface_id}.db`)
    if (!existsSync(file)) { fail(`${code}: no ${config.surface_id}.db`); continue }
    const published = new DatabaseSync(file, { readOnly: true })
    const meta = published.prepare('SELECT generated_at FROM cartridge_meta').get()
    const rows = cartridge.surfaceCartridgeRows(db, config.id, { generatedAt: Number(meta.generated_at) })
    const differences = []
    for (const [table, columns] of Object.entries(cartridge.WIRE_COLUMNS)) {
      const exists = published.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(table)
      if (!exists) {
        if ((rows.tables[table] ?? []).length) differences.push(`${table}: the web writes rows the kit's file has no table for`)
        continue
      }
      const canon = (r) => JSON.stringify(columns.map((c) => {
        if (table === 'surface_config' && c === 'updated') return '·'
        const v = r[c]
        return typeof v === 'bigint' ? Number(v) : (v ?? null)
      }))
      const kit = published.prepare(`SELECT ${columns.join(', ')} FROM ${table}`).all().map(canon).sort()
      const ours = (rows.tables[table] ?? []).map(canon).sort()
      if (JSON.stringify(kit) !== JSON.stringify(ours)) {
        const onlyKit = kit.filter((r) => !ours.includes(r)).length
        const onlyWeb = ours.filter((r) => !kit.includes(r)).length
        differences.push(`${table}: ${onlyKit} row(s) only in the kit's file, ${onlyWeb} only in the web's`)
      }
    }
    published.close()
    if (differences.length) fail(`${code}/${config.surface_id}.db vs the web writer: ${differences.join('; ')}`)
    else console.log(`  ${config.surface_id}.db: the web writer's rows equal the kit's, table for table `
      + `(${Object.values(rows.tables).reduce((n, t) => n + t.length, 0)} rows; surface_config.updated aside)`)
  }
  project.close()
}

if (failures) { console.log(`verify-web: ${failures} failure(s)`); process.exit(1) }
console.log('verify-web: every check passed')
