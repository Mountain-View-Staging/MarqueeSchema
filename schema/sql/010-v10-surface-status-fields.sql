-- v10-surface-status-fields
-- Studio Delivery M3 (PRD 07 §5.6 F-06, §6.1; plan r2 D-r2-21 (a), decided
-- 2026-09-26; Reference §15, the ruling of the same day). Seven nullable
-- columns on surface_status: the DemoStation's status fields.
--
-- The Surface Marquee App PRD §5.8 SurfaceStatus grew the DemoStation PRD
-- §5.8's seven fields in DS M2 (MarqueeNetworkKit e624dcd), sent by a Surface
-- with the mode — the macOS Surface — and absent from every other. v9's table
-- read the App PRD's fields one for one but had no column for these, so the
-- Mac showed them from its LAN server's live registry while a Surface was
-- connected and the web could not show them at all. From here on the row
-- carries them and both Studios show them from the row (D-r2-21 a), by
-- whichever path the report came — the LAN sink, the cloud reader (Delivery
-- M3), a Cache's forwarding (M4).
--
--   mode              'surface' | 'demoStation'
--   screen_source     'display' | 'usbCapture'          what feeds the screen zone
--   layout            'standard' | 'fullScreenMirror' | 'largeDevice'
--   pip_source        'miniPlayer' | 'device'           what the PIP zone shows
--   screen_capture    'ok' | 'noPermission' | 'failed'
--   device_connected  0 | 1                              an iPhone or iPad over USB
--   surface_muted     0 | 1                              the player's playlist audio
--
-- All nullable, no default: a report without the mode writes NULL to each,
-- which is what "absent from the wire" means on the row. The two booleans are
-- INTEGER 0/1, as every boolean in this schema (surface_config.archived,
-- playlist_entry.disabled). A bare check-in (hello / ping) never touches them.
--
-- Additive: an older peer's SurfaceStatusRecord INSERT names none of these and
-- its UPDATE writes around them (Architecture §2.3 R6), so either Studio ships
-- independently. Foreign keys off is fine — nothing here touches a key.
-- Authoring only, never published: both cartridge writers whitelist their
-- tables, and neither names surface_status.
--
-- Rehearsed 2026-09-26 on copies of the four dev shows through both migrators
-- — see the commit and the schema CLAUDE.md.

ALTER TABLE surface_status ADD COLUMN mode             TEXT;
ALTER TABLE surface_status ADD COLUMN screen_source    TEXT;
ALTER TABLE surface_status ADD COLUMN layout           TEXT;
ALTER TABLE surface_status ADD COLUMN pip_source       TEXT;
ALTER TABLE surface_status ADD COLUMN screen_capture   TEXT;
ALTER TABLE surface_status ADD COLUMN device_connected INTEGER;
ALTER TABLE surface_status ADD COLUMN surface_muted    INTEGER;
