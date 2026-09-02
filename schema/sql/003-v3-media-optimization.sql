-- v3-media-optimization
-- The automatic optimizer's LEDGER: what was decided for each
-- (media_file, variant kind) — a rendition was produced ('ready'), the source
-- was already optimal and none is needed ('not_needed'), or the attempt
-- failed ('failed'). Durable on purpose: "don't try this one again" has to
-- survive a relaunch, a cloud pull on another machine, and the peer Studio,
-- and a media_file_variant row cannot carry it — file_name is NOT NULL and
-- unique, and a not-needed outcome has no file (the original already owns
-- that name).
--
-- AUTHORING (main db) ONLY. Cartridge builders DROP this table; the
-- deliverable is still resolved from media_file_variant, so the cartridge
-- artifact schema is unchanged and deployed consumers are unaffected.
--
-- `kind` uses the media_file_variant vocabulary ('optimized' |
-- 'webOptimized' | …). `status` is an open registry as well (constants in
-- MarqueeDataKit and rows.js), not a CHECK constraint. Only OUTCOMES are
-- recorded — "pending" is the absence of a row (or a retryable failure),
-- computed by the reader, so a crash mid-encode can never leave a stale
-- in-progress marker behind. `engine` names what decided (optimizer +
-- media foundation versions + preset); a changed engine string is how a
-- better encoder re-opens settled rows — deliberately, never automatically.
--
-- Additive (new table), so either peer ships independently.

CREATE TABLE media_optimization (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  media_file_id INTEGER NOT NULL REFERENCES media_file(id) ON DELETE CASCADE,
  kind          TEXT    NOT NULL,            -- variant kind the decision is about
  status        TEXT    NOT NULL,            -- 'ready' | 'not_needed' | 'failed'
  reason        TEXT,                        -- the optimizer's skip / failure text
  recipe        TEXT,                        -- the receipt, e.g. 'normalize →HEVC @SSIMU2≥90'
  floor         REAL,                        -- perceptual floor asked (SSIMULACRA2)
  score         REAL,                        -- floor achieved, when measured
  engine        TEXT,                        -- who decided: optimizer + foundation + preset
  attempts      INTEGER NOT NULL DEFAULT 0,  -- runs so far, incl. failures
  created       INTEGER NOT NULL,
  updated       INTEGER NOT NULL
);

CREATE UNIQUE INDEX idx_media_optimization_kind ON media_optimization (media_file_id, kind);
