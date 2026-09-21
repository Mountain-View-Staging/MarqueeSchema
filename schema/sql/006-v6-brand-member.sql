-- v6-brand-member
-- Marks a media_item as a member of a delivered style book.
--
-- ⚠️ Without this the brand never reaches a player, and v5 alone does not fix
-- that. A cartridge carries the REACHABLE closure — media seeded from schedule
-- entries, playlists, playlist entries, and a session set's backing and logo. A
-- typeface is referenced by none of those. It is named only inside style.json,
-- which is a media file's CONTENTS and not something the closure walks.
--
-- So brand media would be imported, sit in the project, and be dropped at
-- publish: a style book that exists everywhere except on the sign.
--
-- The value is the style's portal address — "company/style/version", the same
-- string as project.brand_style — so the seed is a match rather than a
-- convention, and a project carrying two style books over time keeps them
-- apart.
--
-- ⚠️ A COLUMN RATHER THAN A TAG, deliberately. Tags are a user-facing feature
-- on the Editor's rail: a tag is exactly the kind of thing an operator can
-- remove while tidying, and removing this one would drop the fonts from the next
-- publish with nothing to say why until a board came up in the system face. This
-- is not theirs to edit.
--
-- Nullable and additive: every existing media item belongs to no style book,
-- which is what they are today.

ALTER TABLE media_item ADD COLUMN brand_member TEXT;

CREATE INDEX IF NOT EXISTS idx_media_item_brand_member
    ON media_item(brand_member) WHERE brand_member IS NOT NULL;
