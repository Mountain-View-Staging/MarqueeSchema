-- v14-session-board-templates
-- Session board templates (PRD 14, 2026-10-01; the Cartridge Specification's §5.15 at
-- 46cf736, spec PR #15). A session board is rendered from a TEMPLATE PACKAGE — a zip of
-- template.json, the page, its layouts, styles, fonts and a small engine — that the Show,
-- or one session set, names; a Surface carries a built-in default for a Show that names
-- none. The package rides a cartridge as one media file of type application/zip, in the
-- portrait slot of a media item, taken as the manifest names it (never decoded, never
-- renditioned) and wanted on every lane.
--
-- 1. project.template_item_id / session_set.template_item_id: the media item holding the
--    package; the set's overrides the Show's, as a backing does. ON DELETE SET NULL: a
--    template item is archive-not-delete in the UI, and a deleted one leaves the pointer
--    empty rather than refusing.
-- 2. project.template_settings / session_set.template_settings: JSON
--    { "vars": { name: string } } — the Show's values for the variables the template
--    declares, passed through to the template's data document. The settings follow the
--    pointer they sit beside (a set with its own template uses its own; a set without one
--    uses the Show's template with the Show's settings).
-- 3. session_set.render_modes and session_set.schedule_template are DROPPED. Which of a
--    template's layouts a sign shows (now / next, the schedule, or both) is the DEVICE's
--    setting, beside its orientation, never authored; and schedule_template (a layout diff
--    no player ever read) has no successor. No data moves: a set's authored mode was a
--    renderer's choice that the device now makes.
--
-- NOT additive (two columns removed) — the operator's rule of 2026-10-01: no legacy
-- support, the format provides what the app does, not what it did. Both peers take v14 in
-- one cut-over (D-r2-26); a v13 build opens a v14 show read-only through the supersession
-- guard. The wire DDL (spec §4.3, §4.7) changes with it; format_version stays 25.0.1.

ALTER TABLE project ADD COLUMN template_item_id INTEGER REFERENCES media_item(id) ON DELETE SET NULL;
ALTER TABLE project ADD COLUMN template_settings TEXT;
ALTER TABLE session_set ADD COLUMN template_item_id INTEGER REFERENCES media_item(id) ON DELETE SET NULL;
ALTER TABLE session_set ADD COLUMN template_settings TEXT;
ALTER TABLE session_set DROP COLUMN render_modes;
ALTER TABLE session_set DROP COLUMN schedule_template;
