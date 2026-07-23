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

- **Web:** import `dist/migrations.js` — `MIGRATIONS`, `migrate(db)`, `hasBeenSuperseded(db)`,
  `unknownIdentifiers(db)`.
- **Swift:** `MarqueeStore.migrator` delegates to `MarqueeSchema.migrator` from the generated
  `MarqueeSchema.swift`. **Adopted 2026-07-23** — there is no inline migrator and no manual copy
  step: `npm run generate` writes the Swift file straight into
  `SPM/MarqueeDataKit/Sources/MarqueeDataKit/MarqueeSchema.swift` (sibling checkout; skipped
  gracefully when absent) and `npm run check` fails if that copy is stale. Add migrations in
  `schema/` here and regenerate — never in `MarqueeStore.swift`.

## Status

- **1 migration** — `v1-baseline` (the former v1..v14 flattened; see rule 2). Both the Swift and
  JS migrators are generated from `schema/` here; MarqueeDataKit adopts the generated Swift
  directly (see above), so there is one migrator definition, not three.
- **File compatibility proven both directions** (`npm run roundtrip`, 31 checks): JS-authored
  databases open in GRDB with zero migrations run, and JS mutations to a Swift-authored
  database survive a GRDB reopen intact.
- The checkout lease is **not** a schema concern — it lives server-side in R2/KV
  (`_studio/lock.json` + the enable-edit gate), so `v14` is the `edit_code_required` **flag only**
  (a boolean that a gate exists), never a hash or holder. See
  [`MarqueeStudioWeb-Architecture.md`](../MarqueeStudio/MarqueeStudioWeb/Docs/MarqueeStudioWeb-Architecture.md).
- Behavioural contracts (thumbnails, cartridge projection, UUID/hash conventions) still live in
  the architecture doc; move them here as they stabilise.
