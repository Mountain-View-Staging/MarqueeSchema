-- v9-surface-status
-- Studio Delivery M2 (PRD 07 §5.6 F-06, §5.7 F-07, §6.1, §6.4; plan Phase 3
-- "Delivery M2"). One table, one move: where a Surface's status is kept, and
-- the two columns that were its first draft.
--
-- 1. surface_status — one row per location, the latest status report Studio
--    has for it, whichever path it came by (`path`: lan, cache, cloud). The
--    columns read the Surface Marquee App PRD §5.8 SurfaceStatus one for one:
--    the device's `last_update` (its last completed pass, ms), the committed
--    cartridge's (published_revision, generated_at), the media it holds / the
--    manifest total / missing / failed, the entry and rotation set on screen,
--    the last skip / hold / warning, and the app's version and platform. Beside
--    them Studio's own `received_at` and `path`, and `surface_code` so a row
--    still names its Surface when the location is re-assigned. Merging is the
--    store's rule, not the schema's: for each location the newest
--    `last_update` wins, whichever path (F-06).
--
--    location_id is the PRIMARY KEY and REFERENCES surface_location(location_id)
--    (TEXT NOT NULL UNIQUE there — a valid parent key) ON DELETE CASCADE, which
--    is §6.4: deleting a location deletes its status row, on either peer, with
--    no code. A status for a location the show does not have has no row to
--    join and is refused by the store (the PRD's "a spoofed post cannot change
--    anything but that location's status row" needs the row to exist first).
--
--    Authoring schema only, never published: both cartridge writers whitelist
--    their tables (CartridgeFormat.surfaceTables / SURFACE_TABLES), and neither
--    names this one.
--
-- 2. surface_location.last_checked_at and last_pulled_revision MOVE into it
--    (§6.1, last paragraph). They were the LAN check-in's first home (the
--    control channel's hello and ping, MarqueeStore.recordCheckIn), written by
--    Studio's LAN server alone. Each location that has a recorded check-in
--    becomes one status row: path 'lan' (that is the path they came by),
--    last_update and received_at both the check-in time (the check-in carried
--    one clock), published_revision the pulled revision, and every column a
--    check-in never reported left NULL — including `source`, which the Surface
--    reports and a check-in did not. A row whose check-in recorded no time is
--    not carried: last_update and received_at are NOT NULL, and a revision with
--    no date says nothing a Dashboard can show. (recordCheckIn always wrote
--    both, so today that is no row.) Then the two columns are dropped.
--
-- Additive for readers, not for writers: an older peer's SurfaceLocation
-- record names the two dropped columns in its INSERT and UPDATE, so a v8
-- build cannot write a location in a v9 show — the supersession guard
-- (Architecture §2.3 R2) opens it read-only. Both Studios take v9 in one
-- session, as they took v7.
--
-- DROP COLUMN needs SQLite ≥ 3.35 (the floor v7 set); neither column is
-- indexed, referenced or generated. Foreign keys off is fine: the INSERT below
-- reads its parent from the same table it references.
--
-- Rehearsed 2026-09-26 on copies of the four dev shows through both
-- migrators — see the commit and the schema CLAUDE.md.

CREATE TABLE surface_status (
  location_id        TEXT    PRIMARY KEY REFERENCES surface_location(location_id) ON DELETE CASCADE,
  surface_code       TEXT,                      -- the Surface's code, as it reported it
  path               TEXT    NOT NULL,          -- 'lan' | 'cache' | 'cloud': how Studio got it
  last_update        INTEGER NOT NULL,          -- the Surface's lastUpdate, unix ms
  received_at        INTEGER NOT NULL,          -- when Studio stored it, unix ms
  source             TEXT,                      -- the Surface's own source: 'lan' | 'cloud'
  published_revision INTEGER,                   -- committed cartridge
  generated_at       INTEGER,
  media_held         INTEGER,
  media_total        INTEGER,
  media_missing      INTEGER,
  media_failed       INTEGER,
  current_entry_id   INTEGER,
  current_set        TEXT,                      -- 'standard' | 'takeover'
  last_issue_code    TEXT,                      -- the last skip / hold / warning
  last_issue_at      INTEGER,
  app_version        TEXT,
  platform           TEXT                       -- 'macos' | 'ios' | 'windows' | 'linux'
);

INSERT INTO surface_status
  (location_id, surface_code, path, last_update, received_at, published_revision)
  SELECT sl.location_id, sc.surface_id, 'lan', sl.last_checked_at, sl.last_checked_at, sl.last_pulled_revision
  FROM surface_location sl
  JOIN surface_config sc ON sc.id = sl.config_id
  WHERE sl.last_checked_at IS NOT NULL
  ORDER BY sl.id;

ALTER TABLE surface_location DROP COLUMN last_checked_at;
ALTER TABLE surface_location DROP COLUMN last_pulled_revision;
