# test-shows — the generator of the public test shows

**Private.** Generates the shows in `Mountain-View-Staging/marquee-test-shows` (checked out at
`../../../MarqueeTestShows`), which is **PUBLIC**: plan r2 D-r2-25, work items FIX-01 (this) and
FIX-02 (every harness pointed at it). Everything this tool writes is generic — generated pixels,
placeholder text, `Example Company …` presenters — and nothing is read from a real show. Keep it
that way: the public repository's leak scan (`scripts/leak-scan.py` there) runs over every file,
binary media included, but it cannot know what you meant.

## Run

```bash
cd tools/test-shows
swift build -c release
.build/release/test-shows build  ../../../MarqueeTestShows     # regenerate shows/ and legacy/ (~40 s)
.build/release/test-shows verify ../../../MarqueeTestShows     # the Swift checks
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

`build` deletes and rewrites only `shows/RIG26`, `shows/EDIT26` and the `.db` artifacts of
`legacy/` (and the locks). It refuses any folder whose README does not start with
`# Marquee test shows`.

## What it does

- **Through the kit's real write paths** (`MarqueeDataKit` by path, like `swift-reference`):
  `ProjectFactory.create` (the migrator, at the newest identifier), `MediaService.importFile`
  (hash, dimensions, content type, codec, the `original` rendition), `createMediaItem`, the
  store's playlist / entry / window / playback-state / directive / surface / location / schedule /
  session / wallpaper / backing calls, and for every rendition `upsertVariant` plus a ledger row
  (`recordOptimization`) — what Studio's `MediaOptimizationQueue` stores. Only the rendition
  bytes come from here, and the ledger's engine string says so (`marquee test-shows generator 1`),
  so Studio's optimizer treats every file as still owed if a copy is ever opened in Studio.
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
  `tools/fixtures/make-editor-fixture.swift`). Text is drawn with the system UI font; no font is
  shipped.
- **Legacy** (`Legacy.swift`): the migrator stopped at `v2-media-variants`, generic rows in the
  `screen_*` tables, the pre-v25 `cartridge_meta` / `media_manifest` DDL; the tables a cartridge
  never carried dropped.

## The shows, and what they reproduce

| Show | Reproduces (structure only) | |
|---|---|---|
| `RIG26` | VP26 — the harnesses' workhorse: the same seven days (2026-08-27 … 09-02, New York), a portrait-lane-only config (VT1 → `PORT1`), a directive-heavy config (VT2 → `TAKE1`, now on both lanes and with two locations), a DemoStation config (VT3 → `DEMO1`, re-authored for a portrait DemoStation too: branding in both orientations, a transparent and an opaque overlay, a still and a video background), plus what VP26 lacks: a session board with a video backing (the session JSON shaped like SESSDEV1's import), a default backing, wallpapers. | 36 files, 71 renditions, 1,151 directives, 28 sessions |
| `EDIT26` | WFCHI2026X's "TEST — Editor parity" playlist as it was on 2026-09-26 (before the operator's edits): the same 12 rows, windows, flags and entry ids (2–13; row 4 = entry 5), the same three directives, the same day and zone; the sample's rendition pattern per file. Adds a surface (`EDIT1`) so a device can play it. | 7 files, 11 renditions, 3 directives |
| `legacy/` | The two refusals the Surface and SurfaceJS tests used the live `VP26/VT1.db` for. | |

No style book: the only openly licensed face found in the workspace (Inter, OFL 1.1, woff2 only,
without its licence text, under `legacy/mvsmarquee.com/`) was not taken without the lead's
approval. A brand for the brand tests is a follow-up.

## Checks this tool runs

- `verify` (Swift): a copy of each `_studio/Marquee.db` opens with the kit and migrates nothing;
  every cartridge loads in `MarqueeSurfaceEngineLoader` with 0 warnings and reads as v25 through
  the kit's `openCartridge`; every manifest file and offered rendition is on disk at its size and
  hash; on the portrait-only config `filesForLanes([.portrait])` is exactly the manifest minus
  the landscape-only files; the legacy artifacts are refused with `column_missing` / `not_v25`;
  every lock matches.
- `verify-web.mjs`: each show opens through MarqueeStudioWeb's `MarqueeProject.open` (sql.js,
  the pinned `marquee-schema`), writable and at the web's newest identifier; for every surface,
  `cartridge.surfaceCartridgeRows` at the cartridge's `generated_at` equals the kit's file table
  for table (only `surface_config.updated` differs: `markPublished` moved it after the write).
