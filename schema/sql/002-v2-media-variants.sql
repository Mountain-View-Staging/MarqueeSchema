-- v2-media-variants
-- MediaFile children: alternate representations of the same content —
-- optimized, webOptimized, mask, extract, and future kinds — each a real
-- file on disk, with the parent media_file row aware of them.
--
-- AUTHORING (main db) ONLY. Cartridge builders DROP this table and resolve a
-- single deliverable into the existing media_file columns at build time
-- (chosen variant → optimized_file_name + truthful content_hash / file_size /
-- dimensions), so the cartridge artifact schema is unchanged and deployed
-- consumers are unaffected.
--
-- The `kind` vocabulary is an open registry (constants in MarqueeDataKit and
-- rows.js), not a CHECK constraint — a new kind is a registry entry, not a
-- migration. media_file's optimized_file_name / thumbnail_file_name columns
-- are frozen as read-compat mirrors: writers dual-write, readers prefer this
-- table.
--
-- First append-only migration since the 2026-07-23 baseline flatten: Surface
-- clients and legacy-published shows are live, so the baseline is no longer
-- editable in place.

CREATE TABLE media_file_variant (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  media_file_id INTEGER NOT NULL REFERENCES media_file(id) ON DELETE CASCADE,
  kind          TEXT    NOT NULL,            -- 'optimized' | 'webOptimized' | 'mask' | 'extract' | …
  file_name     TEXT    NOT NULL,            -- {uuid}.{ext} in Media/, same minting as every file
  content_type  TEXT,
  width         INTEGER,
  height        INTEGER,
  file_size     INTEGER,
  content_hash  TEXT,                        -- 'sha256:…' of THESE bytes
  codec         TEXT,
  created       INTEGER NOT NULL,
  updated       INTEGER NOT NULL
);

CREATE UNIQUE INDEX idx_media_file_variant_kind ON media_file_variant (media_file_id, kind);
CREATE UNIQUE INDEX idx_media_file_variant_name ON media_file_variant (file_name);
