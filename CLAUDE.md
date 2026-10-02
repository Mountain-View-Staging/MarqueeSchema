# MarqueeSchema

> **2026-10-01 — v14 `session-board-templates` (PRD 14; spec §5.15 at `46cf736`).** `project` and `session_set`
> gain `template_item_id` (→ `media_item`, ON DELETE SET NULL) and `template_settings` (JSON `{ "vars": … }`);
> `session_set.render_modes` and `schedule_template` are DROPPED (the layout a sign shows is the device's board
> variant). NOT additive, by the operator's no-legacy rule; both peers took it in one cut-over. The test-shows
> generator gives BRAND26 two template packages (the Show's and set 2's), zipped from the builder's default
> template through the board kit's `MarqueeSessionBoardTemplate` (its `ZipArchive` and `files` rule, since PRD 14 M5-1 — the same bytes as the published packages); `verify`
> checks both packages ride both lanes and `project.db` keeps the settings and drops the pointer.

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
   - **⚠️ 2026-09-27 — breaking changes are allowed (plan D-r2-26).** The operator lifted
     backward compatibility for everything but the legacy shows: a migration may drop, rename
     or restructure (no additive-only constraint, no compatibility shims), and both Studios
     take it in lock-step — the web's lockfile pinned, the Mac rebuilt; the superseded guard
     stays. Still: a new migration carries the operator's dev shows forward, and 2a holds —
     never edit a migration a database has recorded; add a new one.
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

## `tools/test-shows/` — the generator of the public test shows (2026-09-27, FIX-01)

A SwiftPM tool (the kit, the Surface engine and `webp-swift` by path/URL) that builds the
generic shows of the **PUBLIC** repo `marquee-test-shows` (checkout `../MarqueeTestShows`,
plan D-r2-25): `RIG26` (the workhorse — VP26's structure with generated content), `EDIT26`
(the "Editor parity" sample, entry ids and all) and two pre-v25 artifacts in `legacy/`, through
the kit's real write paths, then publishes with the kit's writer. `test-shows build <checkout>`,
`test-shows verify <checkout>`, `node verify-web.mjs <checkout>` — see its README. Like this
repo, the tool is public, and what it writes is public too, so it writes nothing from a real show. A regeneration is a
deliberate commit in the public repo (file names are the kit's random UUIDs; the encoders vary).

## Consuming it

This repo is **PUBLIC**, and stays so while the live legacy studio (studio.mvsmarquee.com) needs
it: that client reads it and only processes correctly while it is public (the operator,
2026-09-28). It goes private once the legacy studio is no longer supported. Until then everything
committed here is published: no client or brand names, no legacy show codes, no secrets. (The
2026-09-26 note that it was private again was wrong for this repo.) Consumers resolve it by URL
(`github:Mountain-View-Staging/MarqueeSchema`) — pin it in the lockfile's git form, which installs
through the machine's git credentials whatever the visibility (`pnpm update` writes a tarball pin
while the repo is public) — or through the sibling checkout. `package.json` exports `./migrations` → `dist/migrations.js`
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

- **16 migrations** — `v1-baseline` (the former v1..v14 flattened; see rule 2) through
  `v16-retire-style-book`. Both the Swift and JS migrators are generated from
  `schema/` here; MarqueeDataKit adopts the generated Swift directly (see above), so there is
  one migrator definition, not three.
- **`v16-retire-style-book` (2026-10-02, PRD 14 §5.10, M5-6)** — the style book leaves the shows:
  a Show's typefaces, palette and text pair are its session board template's, which the Template
  Builder imports from the brand portal. The items that were only the style book (brand members
  or a project's / set's named book whose files are not image or video) are ARCHIVED, never
  deleted; `project.brand_style` / `brand_style_item_id`, the same pair on `session_set`,
  `media_item.brand_member` and its index are DROPPED (`ALTER TABLE … DROP COLUMN` on a
  column-level `REFERENCES` column works on Apple's SQLite under GRDB too —
  MarqueeDataKit's `testV16ArchivesTheStyleBookAndDropsItsColumns`). The font and JSON content
  types stay in `MediaContentType` so the archived rows decode. `test/roundtrip.mjs` migrates a
  v15 show with a style book through it. Not additive: a v15 build opens a v16 show read-only.
- **`v13-emergency-screens-project-links` (2026-09-28)** — two project-level arrays, authoring
  only: **the cartridge wire is unchanged and no Surface client changes.** Three new tables,
  nothing else touched:
  - `emergency_screen` (`name`, `media_item_id` RESTRICT, `position`): an ordered array of
    named media items. **Publish expands it** (MarqueeDataKit's `emergencyRows`, the web's
    `cartridge.js` `emergencyRows`, the same rule row for row): every playlist a surface
    cartridge carries ends with one `playlist_entry` per screen, in `position` order, from the
    playlist's last position + 1 (0 in an empty one), and every surface cartridge seeds the
    screens' items, so they ride its media manifest whether it has playlists or not. An entry
    with no directive never plays (spec §5.4), so the screens sit dormant on every device.
  - `emergency_screen_directive` (`emergency_screen_id` CASCADE, `timestamp`, `on_screen`,
    `timezone`): the switch. Each row is copied onto that screen's entry in every playlist as an
    **`alert`** directive — the cartridge specification's third type (spec `a34e6d2`, the same
    day): it outranks every takeover, is never scoped to a day, and a Surface cuts to it when it
    commits the cartridge (§5.3 – §5.6, §5.9). Studio activates a screen with one row ON at
    timestamp 0 and clears it by deleting the screen's rows, so an active alert governs on every
    show day and outside the event, whatever a device's clock says. The switch still passes the
    orientation gate like any entry, which is why Studio requires an alert's item to have a file
    in both slots. (The migration's SQL comment, written before the alert type, says takeover;
    an applied migration is never edited.)
  - `project_link` (`name`, `uri`, `position`): the project's documents and file folders, any
    URI scheme. **Never published** — a cartridge sits in a public bucket.
  - The added rows get ids in a reserved range, stable from one publish to the next:
    `1e15 + playlist_id × 1e6 + row id` (the screen's id for an entry, the switch's for a
    directive) — above any AUTOINCREMENT id, inside JavaScript's exact integers. Both writers
    refuse, by name, a row id outside 1…999 999 or a playlist id past the exact range.
  - "Changed since this publish" (STD-11/12) counts both tables in every surface's closure;
    a removed switch stamps its screen and a removed screen stamps every `surface_config`.
  - Additive, but both peers take it in lock-step (D-r2-26): a v12 build opens a v13 show
    read-only through the supersession guard. `format_version` stays 25.0.1.
  - Rehearsed on copies (`sqlite3 .backup`, never in place) of the three public test shows and
    the operator's newest dev show, through the generated JS migrator under sql.js AND the
    Swift one under GRDB (`refgen inspect`): the full `.dump` identical between the two on each,
    the 19 existing tables byte-identical to before, the three new ones empty,
    `foreign_key_check` empty, `integrity_check` ok. `roundtrip.mjs` writes two screens out of
    order, a switch and two links, and reads them back in the array's order (37 checks);
    MarqueeDataKit's `ProjectArraysTests` and the web's `test/projectArrays.test.mjs` cover
    the rest, the web's through the spec's own Loader and engine.
- **`v12-one-schedule` (2026-09-27, ONE-02)** — one schedule per surface (plan D-r2-30; the
  Cartridge Specification §4.4/§5.1 at `d54bd88`, PR #12). `surface_schedule_entry.slot` is
  `playlist` | `demo_station`: a device plays the one scheduled playlist with the files of the
  orientation it renders. By **reading (b)** a config keeps its `landscape` entries when it has
  any, else its `portrait` ones, as `playlist`; the other orientation's entries of a config that
  had both are dropped. By **reading (a)** a `demo_station` entry is branding only — the
  DemoStation's picture-in-picture plays the same playlist in the opposite orientation — so its
  pre-v25 PIP playlist (D3) is cleared, and the CHECK (now the wire's, exactly) refuses one. The
  CHECK changed, so the table is REBUILT: renamed aside, created under its name, filled, the old
  one dropped, `idx_surface_sched_slot (config_id, slot, timestamp)` created again. No table
  references it, so the rename rewrites nothing on either SQLite; ids, clocks and the
  AUTOINCREMENT sequence are kept (the rename carries `sqlite_sequence`'s row on Apple's SQLite,
  node:sqlite and sql.js alike — measured — and the migration copies it to the new table, so a
  dropped entry's id is never reused). **Not additive for an older writer** (a v11 build writes
  `portrait` / `landscape` rows the CHECK refuses): both peers take v12 in the one cut-over, and
  a v11 build opens a v12 show read-only. `format_version` stays 25.0.1 (reading c).
  Rehearsed on copies of the four dev shows (`sqlite3 .backup`, never in place) through the
  generated JS migrator under sql.js AND the Swift one under GRDB (`refgen inspect`), the full
  `.dump` identical between the two on each; `foreign_key_check` empty, `integrity_check` ok:
  **DF26DEV** v4→v12, no schedule; **SESSDEV1** v6→v12, drops entry 12 (config 1's portrait
  "Room21" at Jun 24 13:00, beside its landscape twin, entry 11, same playlist, same instant);
  **VP26** v6→v12, drops entry 5 (VT3's portrait "VP PIP Loop" from Aug 27 00:00) and clears
  demo entry 4's PIP playlist ("VP PIP Loop"; its branding, items 6 and 7, kept) — VT1 keeps its
  two portrait entries and VT2 its landscape one, as `playlist`; **WFCHI2026X** v10→v12, its one
  portrait entry kept as `playlist`. The operator starts a fresh show after this round (D-r2-30),
  so an old show only has to open. `roundtrip.mjs` writes its entry on `playlist` and checks the
  CHECK refuses a retired slot and a demo playlist (34 checks).
- **`v11-device-orientation` (2026-09-27, ORI-02)** — a device's orientation is the device's
  (plan D-r2-24, Reference §15; PRDs 06 §5.7 and 07 §5.7 amended). `surface_location.orientation`
  (the mount, NOT NULL) is dropped: a Surface renders Automatic, or Landscape / Portrait set on
  the device, and the Cartridge Specification retired the column (`9285b01`; a Loader ignores it
  in a cartridge that still has it), so both writers stop emitting it. `surface_status` gains
  `orientation` (TEXT, nullable, `portrait` | `landscape`) — what a Surface reports it renders
  (NetworkKit `SurfaceStatus.orientation`, `6729aeb`), which is where the Dashboard reads it;
  a bare check-in never touches it. **No data moves**: a mount is not a report. **Not additive
  for an older writer** — a v10 location record names the dropped column in its INSERT and
  UPDATE — so both peers take v11 together and a v10 build opens a v11 show read-only. The
  column was not indexed (`idx_surface_location_config` is `config_id` alone), so DROP COLUMN
  is legal; the rows keep their ids and `surface_status` keeps its CASCADE reference.
  Rehearsed on copies of the four dev shows through BOTH migrators, the full `.dump`
  identical between them on each: DF26DEV v4→v11, SESSDEV1 v6→v11 (no locations), VP26
  v6→v11 (VT1-P, VT2-L, VT3-L keep ids and labels; the carried VT1-P check-in intact, its
  `orientation` NULL), WFCHI2026X v10→v11 (LBY1); `foreign_key_check` empty,
  `integrity_check` ok on each.
- **`v10-surface-status-fields` (2026-09-26, Studio Delivery M3)** is additive: seven
  nullable columns on `surface_status` — the DemoStation PRD §5.8's status fields `mode`,
  `screen_source`, `layout`, `pip_source`, `screen_capture`, `device_connected` (0/1),
  `surface_muted` (0/1) — sent by a Surface with the mode (the macOS Surface) and NULL
  for every other, so both Studios show them from the row whichever path the report came
  by (plan D-r2-21 a; Reference §15). No default: absent on the wire is NULL on the row.
  A bare check-in never touches them. An older peer's record names none of them and
  writes around them, so either Studio ships independently. Rehearsed on copies of the
  four dev shows through BOTH migrators with identical facts: DF26DEV v4→v10, SESSDEV1
  and WFCHI2026X v6→v10 with no status rows; VP26 v6→v10, its one carried check-in
  (`VT1-P`, `lan`, pulled rev 2) intact with the seven new columns NULL; the same 25
  columns in the same order on each; `foreign_key_check` empty, `integrity_check` ok.

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
