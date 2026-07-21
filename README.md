# MarqueeSchema

**Source of truth for the Marquee project schema.** Both authoring apps generate from this repo:

```
schema/migrations.json + schema/sql/*.sql        ← edit here, nowhere else
        │
        ├─→ dist/migrations.js         → MarqueeStudioWeb  (sql.js)
        └─→ dist/MarqueeSchema.swift   → MarqueeDataKit    (GRDB)
```

The macOS Studio and the web Studio are **peers over one dataset** — either may author a schema change. That only works if both run identical DDL under identical migration identifiers, which is what this repo enforces.

## Commands

```bash
npm run generate    # regenerate dist/ from schema/
npm run check       # fail if dist/ is stale                       (CI, no Swift)
npm run verify      # fail if schema/ diverges from Swift's output (CI, no Swift)
npm test            # both

npm run swift:build # build the Swift tool                         (macOS)
npm run roundtrip   # sql.js <-> GRDB file-compatibility proof      (macOS)
npm run test:full   # everything
npm run reference   # rebuild the fixture from live MarqueeDataKit  (macOS)
```

`verify` builds a database from `schema/` and compares it structurally to
`test/fixtures/reference.db` — tables, column names/types/nullability/defaults/order,
indexes, and foreign keys. The fixture is produced by the **actual Swift/GRDB
migrator** via `tools/swift-reference/`, so this is a real cross-implementation
check, not a self-consistency check.

Stored DDL *text* is deliberately not compared: SQLite keeps CREATE statements
verbatim, so comment and whitespace differences would produce noise that means nothing.

`roundtrip` is the file-compatibility proof, and the reason to believe the two apps
can hand the same file back and forth:

- **Phase A** — JS authors a project from scratch with sql.js + `dist/migrations.js`;
  GRDB opens it, applies **no** migrations, and decodes every record type.
- **Phase B** — Swift authors a project; JS opens it and adds media files, items, a
  playlist with entries and a directive, a screen with a location and a schedule
  entry, tags, and a project day; Swift reopens and sees exactly those rows. Runs with
  `PRAGMA foreign_keys = ON`, and asserts that the `media_item` CHECK and FK `RESTRICT`
  guards both fire.
- **Supersession** — an unknown identifier is detected by `hasBeenSuperseded`.

31 checks. `npm run swift:build` first — it needs the `refgen` binary.

## Adding a migration

1. Add `schema/sql/0NN-vN-name.sql`.
2. Append an entry to `schema/migrations.json`.
3. `npm run generate`.
4. Copy `dist/MarqueeSchema.swift` into MarqueeDataKit, `npm run reference`, `npm test`.
5. Commit `schema/`, `dist/`, and the refreshed fixture together.

### Rules

**Append-only.** Never reorder, never reuse an identifier, and **never edit the SQL of a
migration that has shipped.** A database records only the *identifier*; if the SQL behind
that identifier changes, every existing database keeps the old shape while the code expects
the new one, and nothing detects it. The loader enforces ordering and uniqueness; it cannot
detect an edit to already-applied SQL. That failure has already happened once — see
"Known incident" below.

**Additive and nullable-or-defaulted.** GRDB's `update` emits `SET` only for columns its
record type encodes, so an older peer opening a newer database preserves columns it does not
know about. That is what lets the two apps ship independently. Requiring a coordinated
release: `NOT NULL` without a default, renames, type changes, dropped columns, and new
tables an old peer must populate to keep an invariant true.

**Check for supersession.** Neither GRDB's `migrate()` nor `dist/migrations.js` errors when
a database carries unknown identifiers — both proceed silently. Callers must check
(`DatabaseMigrator.hasBeenSuperseded(_:)` / `hasBeenSuperseded(db)`) and drop to read-only.

**Always write the bookkeeping.** A database with the right tables but no `grdb_migrations`
rows is *not* compatible — GRDB re-runs `v1-relational` and hard-fails with
`SQLite error 1: table project already exists`. Verified empirically, 2026-07-21. Use
`migrate(db)` from `dist/migrations.js`; never apply the SQL files by hand.

## Known incident — `v8-entry-duration-override`

`v8` was edited in place after shipping, changing a single `start_time`/`end_time` pair into
four per-orientation columns under the **same identifier**. Databases created before the edit
(e.g. `WT Las Vegas.proj`, 2026-07-04) still carry the two-column shape, and GRDB will not
re-run `v8` on them because the identifier is already recorded. The current app's
`PlaylistEntry` expects the four-column shape, so those projects fail on any playlist-entry
query.

This repo exists partly because of that class of bug. `npm run verify` is what catches it.

## Layout

```
schema/migrations.json          manifest — identifiers, order, notes
schema/sql/*.sql                one file per migration
dist/                           GENERATED — do not edit
tools/loader.mjs                read + validate the source of truth
tools/generate.mjs              emit dist/
tools/verify.mjs                structural diff vs the Swift reference
tools/swift-reference/          SwiftPM tool: `create` the fixture, `inspect` any database
                                through the live MarqueeDataKit records
test/roundtrip.mjs              sql.js <-> GRDB file-compatibility proof
test/fixtures/reference.db      checked-in Swift-produced database
```

## Beyond schema

This repo is also the home for cross-implementation contracts that no schema can enforce and
that both apps must agree on — the thumbnail spec, UUID/`sha256:` conventions, and the
cartridge projection rules. See
[`MarqueeStudioWeb/Docs/MarqueeStudioWeb-Architecture.md`](../MarqueeStudio/MarqueeStudioWeb/Docs/MarqueeStudioWeb-Architecture.md)
§2.3, §3.4, §4.1, §5.5; move them here as they stabilise.
