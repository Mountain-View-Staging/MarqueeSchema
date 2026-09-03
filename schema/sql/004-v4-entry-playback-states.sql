-- v4-entry-playback-states
-- Four per-entry playback states for the STUDIO's playlist engine, authored as
-- icons on the Editor's rail rows:
--
--   loop_clip           when this entry becomes active it repeats instead of
--                       passing through — the engine hands the SAME entry back
--   pause_on_entry      the engine cues this entry and HOLDS rather than
--                       playing it, so the operator can take it from preview
--   pause_on_completion the engine holds at the END of this entry instead of
--                       falling through to the next
--   disabled            the engine skips this entry while looking for the next
--                       playable one (an explicit Take still plays it once,
--                       without clearing the flag — standby / "on call" content)
--
-- All four resolve at ONE point: when a duration completes and the engine is
-- asked for the next entry. That is why entry and completion are the same
-- question asked at a boundary ("hold here?" — yes if the outgoing entry says
-- on-completion or the incoming says on-entry), and why precedence needs no
-- rules: loop returns before the pause questions are asked, and disabled is
-- consumed while searching for the next playable entry.
--
-- STUDIO-ONLY BY DESIGN. Entry visibility at a venue is a DIRECTIVE concern,
-- so Surface neither reads nor needs these. They do ride along in screen
-- cartridges, because `playlist_entry` is carried there — which is harmless:
-- extra columns never break a reader, only missing ones do, and the legacy
-- cartridge producer is unaffected because nothing consumes them.
--
-- Additive and defaulted, so either peer ships independently.

ALTER TABLE playlist_entry ADD COLUMN loop_clip           INTEGER NOT NULL DEFAULT 0;
ALTER TABLE playlist_entry ADD COLUMN pause_on_entry      INTEGER NOT NULL DEFAULT 0;
ALTER TABLE playlist_entry ADD COLUMN pause_on_completion INTEGER NOT NULL DEFAULT 0;
ALTER TABLE playlist_entry ADD COLUMN disabled            INTEGER NOT NULL DEFAULT 0;
