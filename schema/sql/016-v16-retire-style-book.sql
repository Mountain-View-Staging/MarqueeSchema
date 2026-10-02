-- v16-retire-style-book
-- The style book leaves the shows (PRD 14 §5.10, M5-6; operator, 2026-10-02; the Cartridge
-- Specification's §9 at retire-style-book). A Show's typefaces, palette and text pair are
-- its session board TEMPLATE's: they travel inside the package (v14), and the Marquee
-- Template Builder imports them from the brand portal. Nothing in a show names a style book
-- any more, and no cartridge delivers one.
--
-- 1. The items that were only the style book — style.json and the typefaces, every item a
--    style address claimed or a project or set named as its book, whose files are not image
--    or video — are ARCHIVED, never deleted (the media rules: archive-not-delete). A brand
--    image or video (a logo) is ordinary media and stays as it is.
-- 2. project.brand_style / brand_style_item_id, the same pair on session_set, and
--    media_item.brand_member (with its index) are DROPPED.
--
-- NOT additive — the operator's rule (D-r2-26): both peers take it in one cut-over; a v15
-- build opens a v16 show read-only through the supersession guard. The wire DDL changes
-- with it (the spec retires the columns, §10.4); format_version stays 25.0.1.

UPDATE media_item SET archived = 1
 WHERE archived = 0
   AND (brand_member IS NOT NULL
        OR id IN (SELECT brand_style_item_id FROM project     WHERE brand_style_item_id IS NOT NULL)
        OR id IN (SELECT brand_style_item_id FROM session_set WHERE brand_style_item_id IS NOT NULL))
   AND NOT EXISTS (SELECT 1 FROM media_file f
                    WHERE f.id IN (media_item.portrait_file_id, media_item.landscape_file_id)
                      AND (f.content_type LIKE 'image/%' OR f.content_type LIKE 'video/%'));

DROP INDEX IF EXISTS idx_media_item_brand_member;
ALTER TABLE media_item  DROP COLUMN brand_member;
ALTER TABLE project     DROP COLUMN brand_style_item_id;
ALTER TABLE project     DROP COLUMN brand_style;
ALTER TABLE session_set DROP COLUMN brand_style_item_id;
ALTER TABLE session_set DROP COLUMN brand_style;
