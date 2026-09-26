-- v8-published-revision
-- Studio Surface Author M1, SCH-01 and the STD-01 repair (Platform Reference
-- v25.0.1 §8.4, §9.5, §15 rulings of 2026-09-26; plan r2 D-r2-11). Two changes,
-- one migration: the counter the project cartridge lacked, and the repair of
-- the rows the pre-STD-01 write path stamped wrongly.
--
-- 1. project.published_revision — a per-show counter, incremented by every
--    project.db publish in the same transaction that reads it, and written into
--    the artifact's cartridge_meta.published_revision. A surface cartridge
--    already carries surface_config.revision; only the project cartridge had no
--    counter, so it shipped 0 with generated_at as its freshness token. A
--    consumer's gate compares (published_revision, generated_at) (Cartridge
--    Spec §8.4), and the counter is what lets it tell a newer project.db from
--    a re-upload of the same one. NOT NULL DEFAULT 0, so an older peer's INSERT
--    of the project row still succeeds and its UPDATE writes around the column
--    (Architecture §2.3 R6). The publisher alone writes it, column-scoped and
--    +1: neither Studio's project record carries it into a whole-row update.
--
-- 2. media_file.content_type and codec, repaired from the `original` rendition.
--    media_file describes the IMPORTED file (STD-01, Cartridge Spec §4.6). Until
--    2026-09-26 the `optimized` dual-write in upsertVariant stamped the row's
--    content_type with the RENDITION's type — an optimized PNG read image/heic —
--    and the importer never named the codec of what it was given. The v25
--    writer reads the original rendition when there is one, so the wire was
--    already right; this makes the authoring row right too. A row whose
--    original names a different type takes that type; a row with no codec takes
--    the original's (COALESCE — a codec the row already names is kept, and an
--    original with no type cannot write NULL into a NOT NULL column). Rows with
--    no `original` row at all — imported before v2-media-variants and never
--    backfilled — are out of reach here: MediaService.backfillOriginalVariants
--    and the web's ensureOriginalRenditions create that row before a publish
--    and repair the parent then. `updated` is left alone: nothing was edited; a
--    wrong value was recorded and is now read correctly.
--
-- Additive: one defaulted column and one UPDATE. Either peer ships
-- independently (Architecture §2.3 R6). Foreign keys off is fine — nothing
-- here touches a key.
--
-- Rehearsed 2026-09-26 on copies of the four dev shows (foreign_key_check
-- empty, integrity_check ok on each): VP26 10 rows retyped and 21 codecs
-- filled, WFCHI2026X 5 retyped, DF26DEV 2 retyped and 2 rows with no original
-- left as they are, SESSDEV1 nothing to repair.

ALTER TABLE project ADD COLUMN published_revision INTEGER NOT NULL DEFAULT 0;

UPDATE media_file SET
  content_type = COALESCE(
    (SELECT v.content_type FROM media_file_variant v
      WHERE v.media_file_id = media_file.id AND v.kind = 'original'),
    content_type),
  codec = COALESCE(
    codec,
    (SELECT v.codec FROM media_file_variant v
      WHERE v.media_file_id = media_file.id AND v.kind = 'original'))
WHERE EXISTS (
  SELECT 1 FROM media_file_variant v
   WHERE v.media_file_id = media_file.id AND v.kind = 'original'
     AND (   (v.content_type IS NOT NULL AND v.content_type <> media_file.content_type)
          OR (media_file.codec IS NULL AND v.codec IS NOT NULL) )
);
