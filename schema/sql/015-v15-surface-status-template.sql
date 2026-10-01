-- v15-surface-status-template
-- PRD 14 §5.7 (F-07), M5-4, 2026-10-01. A Surface's status report says which
-- session board template it is drawing and which of its layouts the device
-- shows — the two facts a sign's operator now sets on the device (the variant)
-- and in Studio (the template) — so both Studios' Dashboards show them from the
-- row, whichever path the report came by (LAN, cloud, a Cache's forwarding):
--
--   template_id       TEXT     the template on screen at the report (template.json
--                              `id`, ≤ 64 [a-z0-9-]); NULL when the default the
--                              Surface carries is drawing, or no board is up
--   template_version  INTEGER  its `version`; NULL with template_id
--   board_variant     TEXT     the device's setting: 'now-next' | 'schedule' | 'both'
--
-- Render failures ride last_issue as before (template.load_failed and friends).
-- Authoring only, never published. Additive and nullable.

ALTER TABLE surface_status ADD COLUMN template_id TEXT;
ALTER TABLE surface_status ADD COLUMN template_version INTEGER;
ALTER TABLE surface_status ADD COLUMN board_variant TEXT
  CHECK (board_variant IS NULL OR board_variant IN ('now-next', 'schedule', 'both'));
