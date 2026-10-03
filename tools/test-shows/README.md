# test-shows — the generator of the public test shows

**Private.** Generates the shows in `Mountain-View-Staging/marquee-test-shows` (checked out at
`../../../MarqueeTestShows`), which is **PUBLIC**: plan r2 D-r2-25, work items FIX-01 (this),
FIX-02 (every harness pointed at it) and FIX-03 (the style book and BRAND26, D-r2-28). Everything
this tool writes is generic — generated pixels, placeholder text, `Example Company …` presenters,
the `example` style book — and nothing is read from a real show. The one thing it ships that it
did not draw is Inter 4.1, from `Resources/Inter-4.1/` (see its `SOURCE.md`), unmodified. Keep it
that way: the public repository's leak scan (`scripts/leak-scan.py` there) runs over every file,
binary media included, but it cannot know what you meant.

## Run

```bash
cd tools/test-shows
swift build -c release
.build/release/test-shows build  ../../../MarqueeTestShows     # regenerate everything (~40 s)
.build/release/test-shows build  ../../../MarqueeTestShows --show BRAND26   # BRAND26 and its style book alone
.build/release/test-shows legacy ../../../MarqueeTestShows     # legacy/ alone, the shows untouched
.build/release/test-shows verify ../../../MarqueeTestShows     # the Swift checks
.build/release/test-shows index  ../../../MarqueeTestShows     # each show's _published.json and lock, nothing regenerated
node --no-warnings verify-web.mjs ../../../MarqueeTestShows      # the web data layer's checks
```

Then, in the public checkout:

```bash
python3 scripts/leak-scan.py
scripts/verify.sh
scripts/budget.sh
node --no-warnings scripts/load-cartridges.mjs --engine ../marquee-cartridge-spec/engine/dist/node.js
```

and commit there. **Push nothing until the lead has reviewed every file** — a push to `main`
deploys `shows/` to GitHub Pages.

`build` deletes and rewrites only what it owns: `shows/RIG26`, `shows/EDIT26`, `shows/BRAND26`,
`brands/` and `LICENSES/Inter-OFL-1.1.txt`, the `.db` artifacts of `legacy/`, and their locks.
`--show <CODE>` (repeatable) builds only the shows named — BRAND26 always with the style book it
imports — and touches nothing else: the other shows keep their files, names and locks, which the
harnesses' numbers depend on (a regeneration renames every file of a show it builds). `legacy/`
is rebuilt only by a full build or `legacy`. It refuses any folder whose README does not start
with `# Marquee test shows`.

## What it does

- **Through the kit's real write paths** (`MarqueeDataKit` by path, like `swift-reference`):
  `ProjectFactory.create` (the migrator, at the newest identifier), `MediaService.importFile`
  (hash, dimensions, content type, codec, the `original` rendition), `createMediaItem`, the
  store's playlist / entry / window / playback-state / directive / surface / location / schedule /
  session / wallpaper / backing calls, and for every rendition `upsertVariant` plus a ledger row
  (`recordOptimization`) — what Studio's `MediaOptimizationQueue` stores. Only the rendition
  bytes come from here, and the ledger's engine string says so (`marquee test-shows generator 1`),
  so Studio's optimizer treats every file as still owed if a copy is ever opened in Studio.
- **The published index** (`PublishedIndex.swift`, PRD 15 F-10): each show's `_published.json`, what
  the Worker writes beside the cartridges on every publish, from the show's own cartridges — the
  Worker's bytes (key order fixed, `project.db` first, MD5 ETags, `updatedAt` the newest
  `generated_at`, so a rewrite over unchanged cartridges is the same bytes). `build` writes it before
  the lock; `index` writes it alone; `verify` holds the file to its cartridges.
- **Publishes** `project.db` and every surface with the kit's writer
  (`publishProjectCartridge`, `publishCartridge`), then checkpoints, closes, sets the authoring
  database to a rollback journal and `VACUUM`s it (one file, no WAL, no free pages holding old
  rows).
- **Fixed clock:** every write takes the next second after a fixed start; publishing happens at
  a fixed instant. `cloud_uid`s are fixed. File names are **not** fixed: the kit's importer mints
  random UUIDs (as in Studio), so a regeneration renames every file. The media encoders
  (VideoToolbox, ImageIO's HEIC) vary run to run. Regeneration is a deliberate new commit.
- **Media** (`Media.swift`): CoreGraphics stills — PNG (opaque stills flattened: no alpha
  channel), PNG with alpha, JPEG, HEIC (ImageIO), WebP (Studio's encoder: `webp-swift`, libwebp
  1.6.0) — and AVFoundation clips (H.264, HEVC; 30 fps; a keyframe a second) with the frame index
  as the Surface harness's barcode (MarqueeSurface `Tests/ConformanceReplay/.../MediaFactory.swift`)
  and as the Studio harness's `frame NNN · SS.SS s` text (MarqueeStudioWeb
  `tools/fixtures/make-editor-fixture.swift`). Text is drawn with the system UI font; the style
  book's mark is drawn in Inter.
- **Legacy** (`Legacy.swift`): the migrator stopped at `v2-media-variants`, generic rows in the
  `screen_*` tables, the pre-v25 `cartridge_meta` / `media_manifest` DDL; the tables a cartridge
  never carried dropped.
- **The style book** (`ExampleStyle.swift`, `Fonts.swift`): `brands/example/example-2026/1/` in the
  branding spec's §7.2 layout, what a portal publishes — `style.json` as the bytes `JSON.stringify`
  writes (the portal's `stampVersion`), the six Inter faces from `Resources/Inter-4.1/` for both
  platforms (each checked against `SOURCE.md`'s hash first), a backing per board canvas and a
  transparent mark drawn in the style's own faces. Every value a producer must measure (spec §9)
  is measured through CoreText, which reads WOFF2 as well as OTF: each file's PostScript name
  (CoreText, CGFont and every `name` record with ID 6), `tabularFigures` from the ten `hmtx`
  digit advances and the `tnum` feature as CoreText shapes it, `lineHeight` from `hhea` (with OS/2
  typo and win and CoreText's own line reported beside it), rounded UP to four places so no client
  reads it as below the metric; and both text inks per row band over each backing (five bands,
  decoded 480 px wide, pixel extremes: the portal's sampler), decided by the kit's
  `Contrast.inkDecision`. The build refuses a book its measurements disagree with, and one whose
  backing needs a scrim. It regenerates byte for byte.
- **BRAND26** (`Brand26.swift`): the style book imported through the kit's
  `MarqueeSessionBoardCartridge.BrandImport.importStyleBook` on the fixed clock — the call Studio
  for Mac's Brand pane makes — then the style's backing and mark selected from its catalogue as
  ordinary media (`Author.importStill`: the portal's files byte for byte, plus renditions), a
  schedule set and a now/next set over one room's 48 sessions, one surface with one schedule.

## The shows, and what they reproduce

| Show | Reproduces (structure only) | |
|---|---|---|
| `RIG26` | VP26 — the harnesses' workhorse: the same seven days (2026-08-27 … 09-02, New York), a config for a portrait sign (VT1 → `PORT1`), a directive-heavy config (VT2 → `TAKE1`, with two locations), a DemoStation config (VT3 → `DEMO1`, re-authored for a portrait DemoStation too: branding in both orientations, a transparent and an opaque overlay, a still and a video background), plus what VP26 lacks: a session board with a video backing (the session JSON shaped like SESSDEV1's import), a default backing, wallpapers. Each config has ONE playlist schedule (plan D-r2-30): a device plays it in the files of its own orientation, and a DemoStation's picture-in-picture plays it in the other orientation's. The "Mini player" playlist VT3's portrait lane once held is scheduled nowhere. | 36 files, 71 renditions, 1,151 directives, 28 sessions |
| `EDIT26` | WFCHI2026X's "TEST — Editor parity" playlist as it was on 2026-09-26 (before the operator's edits): the same 12 rows, windows, flags and entry ids (2–13; row 4 = entry 5), the same three directives, the same day and zone; the sample's rendition pattern per file. Adds a surface (`EDIT1`) so a device can play it. | 7 files, 11 renditions, 3 directives |
| `BRAND26` | SESSDEV1's branding, generically: a style book imported through the kit's `BrandImport` (both platforms' faces as media, the rewritten `style.json`, the `brand_member` marks, the project's reference), a session board in both layouts dressed in the style's backing and mark, one surface whose one schedule plays in either orientation. | 16 files (13 brand members), 5 renditions, 48 sessions |
| `brands/example/example-2026/1` | A style book as the brand portal publishes one — the stand-in portal the brand tests import from (they used SESSDEV1's licensed book). | 12 faces, 3 assets |
| `legacy/` | The two refusals the Surface and SurfaceJS tests used the live `VP26/VT1.db` for. | |

The style book's typeface is Inter 4.1, the official release, approved by the operator on
2026-09-27 (D-r2-28): `Resources/Inter-4.1/` holds the six faces and the OFL exactly as released,
with their hashes in `SOURCE.md`. Download nothing; take a new face only from an official
release, with its licence, into that folder, and record its hash.

⚠️ **Numbers in a style book must print the same in JavaScript and in `JSONSerialization`.**
Studio for Mac's import re-serializes `style.json` with `JSONSerialization`, which writes a double
as `%.17g` (`0.1` → `0.10000000000000001`, `1.4905` → `1.4904999999999999`); the web's
`appleJSON` writes JavaScript's shortest form. They agree on `1.21` and on integers, which is all
this book holds, so the two Studios deliver identical bytes. A `lineHeight` of `1.4905` would not.

## Checks this tool runs

- `verify` (Swift): a copy of each `_studio/Marquee.db` opens with the kit and migrates nothing;
  every cartridge loads in `MarqueeSurfaceEngineLoader` with 0 warnings and reads as v25 through
  the kit's `openCartridge`; every manifest file and offered rendition is on disk at its size and
  hash; on `PORT1` (the portrait sign's config) `filesForLanes([.portrait])` is exactly the
  manifest minus the landscape-only files; on `DEMO1` a host without the DemoStation mode fetches
  PORT1's lanes (the same Rotation, the demo's branding left at the origin) and a DemoStation host
  every file; the legacy artifacts are refused with `column_missing` / `not_v25`;
  every lock matches.
- `verify` also measures the style book again from the published files (`VerifyBrand.swift`):
  spec §9's producer items — each face's name in both formats, both directions per platform;
  the face table's bands against each face's weight class and italic flag; `family` and
  `cssFamily`; `tabularFigures`; `lineHeight` at or above every face's metric; the board's
  characters; each web face the same face as its source; every face and the licence the
  release's bytes; `palette.primary` and both text inks, `#RRGGBB`, each text colour at 3:1 in
  its own context (the derived `mutedOnDark` too); both inks per band over each backing, and a
  synthetic black-to-white backing reported as needing a scrim; every asset at its declared
  pixel size — and BRAND26 through the kit: the reference, the 13 members byte for byte the
  portal's, the delivered `style.json` re-derived with `JSONSerialization`, the sets dressed in
  the style's assets, `BRAND1.db` carrying every member in every lane, `project.db` keeping only
  the address, and `BrandDelivery.register(manifest:locate:)` — the Surface's route —
  registering the six Apple faces from the show folder cleanly and building the book's brand,
  whose boards pick the dark ink over the delivered backings.
- `verify-web.mjs`: each show opens through MarqueeStudioWeb's `MarqueeProject.open` (sql.js,
  the pinned `marquee-schema`), writable and at the web's newest identifier; for every surface,
  `cartridge.surfaceCartridgeRows` at the cartridge's `generated_at` equals the kit's file table
  for table (only `surface_config.updated` differs: `markPublished` moved it after the write).
  Then the style book through the web's import rules (`src/services/brandImport.js`): the
  portal's `style.json` is `JSON.stringify`'s bytes; every face, both formats, is the face it is
  named for by MarqueeSurfaceJS's `fontinfo.js` (the browser Surface's reader — so the sibling
  `../../../MarqueeStudio/MarqueeSurfaceJS` checkout is needed too); the web's
  `rewriteStyleBook` + `appleJSON` give BRAND26's delivered `style.json` byte for byte; and the
  web's `recordBrandImport` over the same files leaves the kit's rows.
