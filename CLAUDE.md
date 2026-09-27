# MarqueeSchema

Cross-implementation **source of truth** for the Marquee project schema and the contracts
that surround it. Consumed by `SPM/MarqueeDataKit` (Swift/GRDB) and
`MarqueeStudio/MarqueeStudioWeb` (JS/sql.js).

> Part of [MVSCollective](../CLAUDE.md). Created 2026-07-21 when the macOS Studio and the web
> Studio became **peers over one dataset** rather than owner and client — see the governance
> amendment in [`MarqueeStudio/AGENT_BRIDGE.md`](../MarqueeStudio/AGENT_BRIDGE.md).

## Why this repo exists

Two apps now author the same SQLite file. Neither one's source can be the schema's home:
"generate the JS from the Swift" is the old ownership rule with extra steps, and the reverse
has the same defect. So the DDL lives here, platform-neutral, and both sides are generated.

## Rules — read before touching anything

1. **`schema/` is the only place to edit.** `dist/` is generated; edits there are lost on the
   next `npm run generate` and cause `npm run check` to fail in CI.
2. **⚠️ PRE-MVP BASELINE MODE (since 2026-07-23).** The former v1..v14 append-only history was
   flattened into a single `v1-baseline` because nothing consumes these databases with a shipped
   MVP client yet. **Until an MVP client ships, the baseline SQL may be edited in place** — just
   regenerate and re-verify. Once one ships, switch back to append-only (rules 2a/2b below), so
   deployed databases can still migrate. Any pre-baseline database (old grdb_migrations) opens as
   *superseded* and read-only — recreate it.
   - **2a. Append-only (post-MVP).** Never reorder, never reuse an identifier, and **never edit a
     shipped migration's SQL.** Databases record only the identifier — change the SQL behind it
     and every existing database silently keeps the old shape. See the `v8` incident in
     [README.md](README.md); it has already bitten this project once.
   - **2b. Additive, nullable-or-defaulted changes only** (post-MVP), unless coordinating a
     release of both apps. This is what lets the two peers ship independently.
4. **Regenerate and verify before committing:** `npm test`. On macOS, refresh the Swift
   fixture first with `npm run reference` whenever `MarqueeDataKit`'s migrator changes.

## Build / test

```bash
npm run generate    # schema/ → dist/
npm test            # check dist/ is current + verify against the Swift reference
npm run reference   # rebuild test/fixtures/reference.db from live MarqueeDataKit (macOS)
```

No dependencies. `tools/` uses `node:sqlite`, which needs **Node ≥ 22.5**; on 22.x it emits an
experimental warning, hence `--no-warnings` in the scripts.

`tools/swift-reference/` is a throwaway SwiftPM executable that builds a database using the
*live* `MarqueeDataKit` migrator via a relative path dependency (`../../../SPM/MarqueeDataKit`).
It exists so `verify` is a genuine cross-implementation check rather than a self-consistency
one. It requires the sibling checkout and macOS 15+.

## Consuming it

This repo is **public** (`github:Mountain-View-Staging/MarqueeSchema`) so consumers can resolve
it by URL without the sibling checkout. `package.json` exports `./migrations` → `dist/migrations.js`
(dist is committed), and `files` ships `dist` + `schema`.

- **Web:** depend on `"marquee-schema": "github:Mountain-View-Staging/MarqueeSchema"` and import
  `marquee-schema/migrations` — `MIGRATIONS`, `migrate(db)`, `hasBeenSuperseded(db)`,
  `unknownIdentifiers(db)`, `KNOWN_IDENTIFIERS`. pnpm pins the commit in the lockfile; run
  `pnpm update marquee-schema` after pushing a schema change to pick it up (it no longer
  auto-reflects like the old `link:` did).
- **Swift:** `MarqueeStore.migrator` delegates to `MarqueeSchema.migrator` from the generated
  `MarqueeSchema.swift`. **Adopted 2026-07-23** — there is no inline migrator and no manual copy
  step: `npm run generate` writes the Swift file straight into
  `SPM/MarqueeDataKit/Sources/MarqueeDataKit/MarqueeSchema.swift` (sibling checkout; skipped
  gracefully when absent) and `npm run check` fails if that copy is stale. Add migrations in
  `schema/` here and regenerate — never in `MarqueeStore.swift`.

## Status

- **9 migrations** — `v1-baseline` (the former v1..v14 flattened; see rule 2) through
  `v9-surface-status`. Both the Swift and JS migrators are generated from `schema/` here;
  MarqueeDataKit adopts the generated Swift directly (see above), so there is one migrator
  definition, not three.
- **`v9-surface-status` (2026-09-26, Studio Delivery M2)** adds `surface_status` — one row
  per location, the latest status a Studio holds for it whichever path it came by (`path`:
  `lan` / `cache` / `cloud`), reading the Surface App PRD §5.8 `SurfaceStatus` column for
  column plus Studio's `received_at` — with `location_id` as PRIMARY KEY referencing
  `surface_location(location_id)` **ON DELETE CASCADE** (Delivery PRD §6.4, so a deleted
  location takes its row on either peer with no code). `surface_location.last_checked_at` /
  `last_pulled_revision` MOVE into it: each recorded check-in becomes a path-`lan` row (both
  clocks the check-in time, the pulled revision, no `source` — a check-in never named one),
  then the two columns are dropped. Authoring only, never published (both writers whitelist
  their tables). **Not additive for an older writer**: a v8 record names the dropped columns
  in its INSERT/UPDATE, so both peers take v9 together and a v8 build opens a v9 show
  read-only. The merge rule (newest `last_update` wins; a bare check-in never outranks a
  report) is the stores', not the schema's: `MarqueeStore+SurfaceStatus.swift` and the
  web's `surfaceStatusRepo.js`. Rehearsed on copies of the four dev shows through BOTH
  migrators with identical facts: DF26DEV v4→v9, SESSDEV1 and WFCHI2026X v6→v9, no
  check-ins to carry; VP26 v6→v9, its one check-in (`VT1-P`, `VT1`, 2026-09-25, pulled
  rev 2) carried as a `lan` row; `foreign_key_check` empty, `integrity_check` ok on each.
- **`v8-published-revision` (2026-09-26)** is additive: `project.published_revision`, the
  per-show counter every `project.db` publish increments in the transaction that reads it and
  stamps into `cartridge_meta` (SCH-01; surface cartridges keep `surface_config.revision`),
  plus the STD-01 repair — `media_file.content_type` / `codec` taken from the `original`
  rendition where the row differs. Rows with no `original` row are the backfill's
  (`MediaService.backfillOriginalVariants`, the web's `ensureOriginalRenditions`), not the
  migration's. **A migration's UPDATE must never be able to write NULL into a NOT NULL
  column** — v8 COALESCEs, and its fixture row 5 (an original with no type) is why.
  Rehearsed on copies of the four dev shows through BOTH migrators with identical results
  (VP26 10 retyped + 21 codecs, WFCHI2026X 5, DF26DEV 2 + 2 unreachable, SESSDEV1 0;
  `foreign_key_check` empty, `integrity_check` ok).
- **`v7-surface-author` (2026-09-26) is the one NON-additive migration since the baseline**, by
  decision (PRD 06 §6.1, Reference §2.4): `screen_*` → `surface_*`, `project.backing_item_id`
  added, the per-slot backing/overlay columns and `playlist.shuffle` dropped. Both Studios took it
  in one session; a v6 build opens a v7 show read-only through the supersession guard, and a v7
  build cannot open a v6 show for writing until it migrates it — which either Studio does on open.
  ⚠️ **Apple's system SQLite defaults `legacy_alter_table` ON**, and GRDB runs migrations with
  foreign keys off, so `ALTER TABLE … RENAME TO` there does NOT rewrite other tables' REFERENCES
  clauses (measured: a renamed `surface_location` kept `REFERENCES screen_config(id)`). v7
  therefore rebuilds the two child tables instead of renaming them. Any future rename of a
  table that others reference must do the same.
  Cartridges published from a v7 show carry `surface_*` tables, which the pre-v25 Surfaces
  (reading `screen_*` through MarqueeDataKit) cannot open — the intended v25 break; the Surface
  work restores playback through the engine's Loader.
- **File compatibility proven both directions** (`npm run roundtrip`, 31 checks): JS-authored
  databases open in GRDB with zero migrations run, and JS mutations to a Swift-authored
  database survive a GRDB reopen intact.
- The checkout lease is **not** a schema concern — it lives server-side in R2/KV
  (`_studio/lock.json` + the enable-edit gate), so `v14` is the `edit_code_required` **flag only**
  (a boolean that a gate exists), never a hash or holder. See
  [`MarqueeStudioWeb-Architecture.md`](../MarqueeStudio/MarqueeStudioWeb/Docs/MarqueeStudioWeb-Architecture.md).
- Behavioural contracts (thumbnails, cartridge projection, UUID/hash conventions) still live in
  the architecture doc; move them here as they stabilise.

## ⚠️ Third cartridge producer until the legacy studio retires (~Oct 2026)

The LEGACY web studio (studio.mvsmarquee.com) publishes **client-side-generated v1-baseline
SQLite cartridges** into the same `<CODE>/<FILE>.db` keyspace, via the Worker's
`legacyPublish` route — and Surface consumes them indistinguishably from ours. It sits
**outside** this repo's generated-migrator + equivalence-test net.

**Any change to the CARTRIDGE schema (the per-type trimmed subset, not just the authoring
schema) must include adjusting the legacy app's cartridge generator to stay conformant** —
or a decision that legacy shows tolerate the skew. **v7 took the second road (2026-09-26):**
the legacy generator keeps writing `screen_*` cartridges, which is what the pre-v25 Surfaces
its two live shows run on read; it is frozen until the conference ends and retires with it. Dustin, 2026-08-31: the legacy app is
being forced off its S3 dependency and onto the web studio within ~a month; delete this
section when that migration lands. (The 2026-08 media-variant work deliberately left the
cartridge schema untouched — that discipline is what has protected legacy so far.)
