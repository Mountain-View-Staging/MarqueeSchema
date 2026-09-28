-- v13-emergency-screens-project-links
-- Two project-level additions (the operator, 2026-09-28). Authoring only: the
-- Cartridge Specification's wire is unchanged, and no Surface client changes.
--
-- 1. EMERGENCY SCREENS. An ordered array of { name, media item }. At publish,
--    each writer (MarqueeDataKit, the web's cartridge.js) appends one entry per
--    emergency screen to the END of every playlist a surface cartridge carries,
--    in `position` order, so the items ride every cartridge's media manifest and
--    every device holds them ahead of time. An entry with no directive never
--    plays (spec §5.4), so they sit dormant.
--
--    An emergency screen is switched on by an emergency_screen_directive — what
--    Studio's UI writes: ON at 12:00:00 AM of the current venue day, so it is in
--    force the moment a device commits the cartridge. The writer copies each such
--    directive onto that screen's entry in every playlist as a TAKEOVER directive,
--    and a Surface cuts to it as it cuts to any takeover (spec §5.5, §5.9).
--    Directives are day-scoped (spec §5.4): an ON lapses when its venue day ends.
--    OFF (on_screen 0) clears it.
--
--    The rows a writer adds get ids in a reserved range, stable across publishes:
--    1e15 + playlist_id * 1e6 + the emergency screen's (or directive's) id — above
--    any AUTOINCREMENT id, inside JavaScript's exact integers.
--
-- 2. PROJECT LINKS. An ordered array of { name, uri }: project documents and
--    file folders, for the people running the show. Never published — no
--    cartridge carries it (a cartridge sits in a public bucket).
--
-- Additive (three new tables), but both peers take it in lock-step (D-r2-26): a
-- v12 build opens a v13 show read-only through the supersession guard.

CREATE TABLE emergency_screen (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  name          TEXT    NOT NULL,
  media_item_id INTEGER NOT NULL REFERENCES media_item(id) ON DELETE RESTRICT,
  position      INTEGER NOT NULL,            -- the array's order; and the order at the end of every playlist
  created       INTEGER NOT NULL,
  updated       INTEGER NOT NULL
);

CREATE INDEX idx_emergency_screen_position ON emergency_screen (position);

CREATE TABLE emergency_screen_directive (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  emergency_screen_id INTEGER NOT NULL REFERENCES emergency_screen(id) ON DELETE CASCADE,
  timestamp           INTEGER NOT NULL,      -- Unix ms; the UI writes 12:00:00 AM of the current venue day
  on_screen           INTEGER NOT NULL,      -- 1 = on (a takeover), 0 = cleared
  timezone            TEXT,                  -- authoring context only, as directive.timezone
  created             INTEGER NOT NULL,
  updated             INTEGER NOT NULL
);

CREATE INDEX idx_emergency_screen_directive_screen ON emergency_screen_directive (emergency_screen_id, timestamp);

CREATE TABLE project_link (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  name     TEXT    NOT NULL,
  uri      TEXT    NOT NULL,
  position INTEGER NOT NULL,                 -- the array's order
  created  INTEGER NOT NULL,
  updated  INTEGER NOT NULL
);

CREATE INDEX idx_project_link_position ON project_link (position);
