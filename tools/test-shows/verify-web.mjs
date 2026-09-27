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

  Then the style book (FIX-03), `brands/example/example-2026/1/`, through the web's import rules
  (src/services/brandImport.js): the portal's style.json is JSON.stringify's bytes; every face,
  OTF and WOFF2, is the face it is named for by MarqueeSurfaceJS's fontinfo.js; the web's
  rewrite gives BRAND26's delivered style.json byte for byte; the web's recordBrandImport over
  the same files leaves the kit's rows.

  Needs the sibling checkouts ../../../MarqueeStudio/MarqueeStudioWeb (with its node_modules) and
  ../../../MarqueeStudio/MarqueeSurfaceJS (src/fontinfo.js, which has no dependencies).
*/
import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { createHash } from 'node:crypto'
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

// ── The style book (FIX-03), through the web's import rules ────────────────────────────────
//
// `brands/example/example-2026/1/` is a stand-in portal. Imported by the web's own rules
// (src/services/brandImport.js: declaredFaces, rewriteStyleBook, appleJSON) it must give
// BRAND26's delivered style.json byte for byte — the bytes the kit's BrandImport wrote — and
// the web's recordBrandImport over the same files must leave the kit's rows. Every face is
// also read a second way, by MarqueeSurfaceJS's fontinfo.js (the reader the browser Surface
// holds a delivered style book to): in both formats it is the face the book says it is.
{
  const {
    brandAddress, baseName, brandContentType, declaredFaces, rewriteStyleBook, appleJSON,
    manifestFileName, manifestItemName,
  } = await import(new URL('src/services/brandImport.js', web))
  const { fontInfo } = await import(new URL('../MarqueeSurfaceJS/src/fontinfo.js', web))
  const styleRoot = join(repo, 'brands/example/example-2026/1')
  const text = readFileSync(join(styleRoot, 'style.json'), 'utf8')
  const book = JSON.parse(text)
  const address = brandAddress(book.company, book.style, book.version)
  if (JSON.stringify(book) !== text) fail('style.json is not the bytes the portal publishes (JSON.stringify)')

  const faces = declaredFaces(book)
  const named = new Set([...book.fonts.family.faces.flatMap((f) => [f.regular, f.italic]), book.fonts.family.display].filter(Boolean))
  const byFace = new Map()
  for (const { platform, declared } of faces) {
    const info = fontInfo(join(styleRoot, declared))
    const face = baseName(declared).replace(/\.[^.]+$/, '')
    if (info.postScriptName !== face || !named.has(face)) fail(`${declared}: fontinfo reads ${info.postScriptName}`)
    const other = byFace.get(face)
    if (other && (other.weight !== info.weight || other.italic !== info.italic)) fail(`${face}: the ${platform} file is weight ${info.weight}, italic ${info.italic}; its source ${other.weight}, ${other.italic}`)
    byFace.set(face, info)
  }
  console.log(`style book ${address}: ${faces.length} faces read by MarqueeSurfaceJS's fontinfo.js, each the face it is named for `
    + `(${[...byFace.values()].map((i) => `${i.postScriptName} ${i.weight}${i.italic ? 'i' : ''}`).join(', ')})`)

  const show = join(repo, 'shows/BRAND26')
  const kit = await MarqueeProject.open(readFileSync(join(show, '_studio/Marquee.db')))
  const project = kit.db.get('SELECT brand_style, brand_style_item_id FROM project')
  const items = kit.db.all('SELECT * FROM media_item WHERE brand_member = ? ORDER BY id', [address])
  const fileRow = (id) => kit.db.get('SELECT * FROM media_file WHERE id = ?', [id])
  const manifestItem = items.find((i) => i.id === project.brand_style_item_id)
  const faceItems = items.filter((i) => i !== manifestItem)
  if (project.brand_style !== address) fail(`BRAND26 is branded ${project.brand_style}`)
  if (!manifestItem || manifestItem.name !== manifestItemName(address)) fail('BRAND26: no manifest item by the web\'s name')
  if (faceItems.length !== faces.length) fail(`BRAND26: ${faceItems.length} face items for ${faces.length} declared faces`)

  // The kit imports in the web's order: platforms sorted, faces as declared.
  const delivered = new Map()
  faces.forEach(({ declared }, i) => {
    const item = faceItems[i]
    const file = item && fileRow(item.portrait_file_id)
    if (!file || item.name !== baseName(declared) || file.original_file_name !== baseName(declared)
      || file.content_type !== brandContentType(declared)) {
      fail(`BRAND26: face ${i + 1} is ${item?.name} (${file?.content_type}), the web expects ${baseName(declared)} (${brandContentType(declared)})`)
      return
    }
    delivered.set(declared, file.source_file_name)
  })
  const manifestFile = manifestItem && fileRow(manifestItem.portrait_file_id)
  const bytes = appleJSON(rewriteStyleBook(book, delivered))
  const kitBytes = manifestFile ? readFileSync(join(show, manifestFile.source_file_name), 'utf8') : ''
  if (bytes !== kitBytes) fail('the web\'s rewrite of style.json is not the kit\'s delivered bytes')
  else if (`sha256:${createHash('sha256').update(bytes).digest('hex')}` !== manifestFile.source_hash) fail('the delivered style.json\'s hash is not its source_hash')
  else console.log(`  the web's rewrite (rewriteStyleBook + appleJSON) = BRAND26's delivered style.json, byte for byte (${Buffer.byteLength(bytes)} B)`)
  if (manifestFile && manifestFile.original_file_name !== manifestFileName(book.company, book.style, book.version)) fail('the manifest\'s original name is not the web\'s')

  // The web's recordBrandImport over the same files leaves the kit's rows.
  const descriptor = (file) => ({
    sourceFileName: file.source_file_name, contentType: file.content_type, fileSize: file.file_size,
    sourceHash: file.source_hash, originalFileName: file.original_file_name, source: file.source,
  })
  const at = manifestItem.created
  const peer = await MarqueeProject.create({ name: 'Brand check', projectCode: 'BRANDCHK', timezone: 'America/Los_Angeles' })
  peer.recordBrandImport(address,
    faceItems.map((item) => ({ name: item.name, descriptor: descriptor(fileRow(item.portrait_file_id)) })),
    { name: manifestItem.name, descriptor: descriptor(manifestFile) }, at)
  const rowsOf = (p) => {
    const names = new Map(p.db.all('SELECT id, source_file_name FROM media_file').map((f) => [f.id, f.source_file_name]))
    const strip = (row, keys) => JSON.stringify(Object.fromEntries(Object.entries(row).filter(([k]) => !keys.includes(k))
      .map(([k, v]) => [k, k.endsWith('file_id') ? names.get(v) ?? v : typeof v === 'bigint' ? Number(v) : v])))
    const brandItems = p.db.all('SELECT * FROM media_item WHERE brand_member = ? ORDER BY id', [address])
    const fileIds = brandItems.map((i) => i.portrait_file_id)
    const project = p.db.get('SELECT brand_style, brand_style_item_id FROM project')
    return {
      items: brandItems.map((r) => strip(r, ['id'])),
      files: fileIds.map((id) => strip(p.db.get('SELECT * FROM media_file WHERE id = ?', [id]), ['id'])),
      variants: fileIds.flatMap((id) => p.db.all('SELECT * FROM media_file_variant WHERE media_file_id = ? ORDER BY kind', [id])
        .map((r) => strip(r, ['id']))),
      project: `${project.brand_style} → ${brandItems.find((i) => i.id === project.brand_style_item_id)?.name}`,
    }
  }
  const ours = rowsOf(peer), theirs = rowsOf(kit)
  for (const key of ['items', 'files', 'variants']) {
    const differing = theirs[key].filter((row, i) => row !== ours[key][i]).length + Math.abs(theirs[key].length - ours[key].length)
    if (differing) fail(`recordBrandImport: ${differing} ${key} row(s) differ from the kit's — e.g. ${theirs[key].find((row, i) => row !== ours[key][i])} vs ${ours[key].find((row, i) => row !== theirs[key][i])}`)
  }
  if (ours.project !== theirs.project) fail(`recordBrandImport: the project reads ${ours.project}, the kit's ${theirs.project}`)
  console.log(`  the web's recordBrandImport leaves the kit's rows: ${ours.items.length} items, ${ours.files.length} files, `
    + `${ours.variants.length} renditions, project ${ours.project}`)
  peer.close()
  kit.close()
}

if (failures) { console.log(`verify-web: ${failures} failure(s)`); process.exit(1) }
console.log('verify-web: every check passed')
