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
2. **Append-only.** Never reorder, never reuse an identifier, and **never edit a shipped
   migration's SQL.** Databases record only the identifier — change the SQL behind it and
   every existing database silently keeps the old shape. See the `v8` incident in
   [README.md](README.md); it has already bitten this project once.
3. **Additive, nullable-or-defaulted changes only**, unless you are coordinating a release of
   both apps. This is what lets the two peers ship independently.
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
- **Swift:** copy `dist/MarqueeSchema.swift` into `MarqueeDataKit` and have `MarqueeStore` use
  `MarqueeSchema.migrator`. **Not yet wired** — `MarqueeStore.swift` still declares its own
  migrator inline. The generated file is verified byte-equivalent in behaviour, but adopting it
  is a Swift-side change Dustin is picking up.

## Status

- 13 migrations (`v1-relational` … `v13-project-days`), transcribed from `MarqueeStore.swift`
  and **verified structurally identical** to Swift's output.
- `v14-project-checkout` is specified but **not yet added** — see
  [`MarqueeStudioWeb-Architecture.md`](../MarqueeStudio/MarqueeStudioWeb/Docs/MarqueeStudioWeb-Architecture.md) §3.2.1.
- Behavioural contracts (thumbnails, cartridge projection, UUID/hash conventions) still live in
  the architecture doc; move them here as they stabilise.
