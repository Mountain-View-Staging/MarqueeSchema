-- v12-one-schedule
-- ONE-02 (plan r2 D-r2-30, decided 2026-09-27; Reference §15; the Cartridge
-- Specification's §4.4 and §5.1 at d54bd88, spec PR #12). One schedule per
-- surface: a surface schedules playlists in ONE slot, not a portrait and a
-- landscape one. A playlist already carries both orientations in its items'
-- slots, and a device plays the scheduled playlist with the files of the
-- orientation it renders (D-r2-24). Two surfaces that need different content
-- per orientation are two configs.
--
-- 1. surface_schedule_entry.slot becomes 'playlist' | 'demo_station'. The
--    playlist rows are carried by reading (b), ratified by the operator: a
--    config keeps its 'landscape' entries when it has any, else its
--    'portrait' ones, as 'playlist'. The other orientation's entries of a
--    config that had both are dropped (the rehearsal lists them). Ids,
--    timestamps, playlists and clocks are kept.
--
-- 2. A 'demo_station' entry is branding only (reading (a)): the DemoStation's
--    picture-in-picture plays the SAME scheduled playlist, with the files of
--    the opposite orientation (spec §5.11). The pre-v25 PIP playlist a demo
--    row could carry (D3) is dropped: its playlist_id becomes NULL, and the
--    CHECK now forbids one — the wire's CHECK, exactly.
--
-- 3. The CHECK changes, so the table is rebuilt: renamed aside, created under
--    its name with the new CHECK, filled, the old one dropped, and the index
--    idx_surface_sched_slot (config_id, slot, timestamp) created again. No
--    table references surface_schedule_entry, so the rename rewrites nothing
--    on either SQLite (Apple's defaults legacy_alter_table ON; the v7 note in
--    the schema CLAUDE.md), and the table's own references are its new DDL's.
--    AUTOINCREMENT keeps its promise across the rebuild: the new table's
--    sequence is the old one's, so a dropped entry's id is never reused.
--
-- Values other than 'portrait', 'landscape' and 'demo_station' never passed the
-- v7 CHECK, so there are none to carry.
--
-- NOT additive for an older writer: a v11 build writes 'portrait' and
-- 'landscape' rows, which the new CHECK refuses — both peers take v12 in one
-- cut-over (D-r2-26), and a v11 build opens a v12 show read-only through the
-- supersession guard. format_version stays 25.0.1 (reading (c)).
--
-- Rehearsed on copies of the four dev shows through both migrators — see the
-- commit and the schema CLAUDE.md.

ALTER TABLE surface_schedule_entry RENAME TO surface_schedule_entry_v11;

CREATE TABLE surface_schedule_entry (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  config_id          INTEGER NOT NULL REFERENCES surface_config(id) ON DELETE CASCADE,
  slot               TEXT    NOT NULL,            -- 'playlist' | 'demo_station'
  timestamp          INTEGER NOT NULL,            -- most-recent <= now wins, per slot
  playlist_id        INTEGER REFERENCES playlist(id)   ON DELETE RESTRICT,  -- the playlist slot's; NULL = an authored blank
  background_item_id INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (behind)
  overlay_item_id    INTEGER REFERENCES media_item(id) ON DELETE RESTRICT,  -- demo branding (front)
  created            INTEGER NOT NULL,
  updated            INTEGER NOT NULL,
  -- A playlist entry carries only a playlist (NULL: an authored blank). A demo
  -- entry carries branding only — the picture-in-picture plays the one
  -- schedule's playlist; an overlay still requires a background, and all-NULL =
  -- exit demo mode. The wire's CHECK (Cartridge Specification §4.4).
  CHECK (
    ( slot = 'playlist'
        AND background_item_id IS NULL AND overlay_item_id IS NULL )
    OR
    ( slot = 'demo_station'
        AND playlist_id IS NULL
        AND ( background_item_id IS NOT NULL OR overlay_item_id IS NULL ) )
  )
);

INSERT INTO surface_schedule_entry
  (id, config_id, slot, timestamp, playlist_id, background_item_id, overlay_item_id, created, updated)
  SELECT e.id, e.config_id,
         CASE WHEN e.slot = 'demo_station' THEN 'demo_station' ELSE 'playlist' END,
         e.timestamp,
         CASE WHEN e.slot = 'demo_station' THEN NULL ELSE e.playlist_id END,
         e.background_item_id, e.overlay_item_id, e.created, e.updated
  FROM surface_schedule_entry_v11 e
  WHERE e.slot = 'demo_station'
     OR e.slot = 'landscape'
     OR ( e.slot = 'portrait'
          AND NOT EXISTS ( SELECT 1 FROM surface_schedule_entry_v11 l
                           WHERE l.config_id = e.config_id AND l.slot = 'landscape' ) )
  ORDER BY e.id;

-- The new table's sequence is the old one's (AUTOINCREMENT: never reuse an id).
DELETE FROM sqlite_sequence WHERE name = 'surface_schedule_entry';
INSERT INTO sqlite_sequence (name, seq)
  SELECT 'surface_schedule_entry', seq FROM sqlite_sequence WHERE name = 'surface_schedule_entry_v11';

DROP TABLE surface_schedule_entry_v11;

CREATE INDEX idx_surface_sched_slot ON surface_schedule_entry (config_id, slot, timestamp);
