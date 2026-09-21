-- v5-brand-style
-- Which style book a project — or one session set — is branded with.
--
-- Two columns per table, because they answer two different questions and
-- collapsing them would lose one:
--
--   brand_style          PROVENANCE: "company/style/version" exactly as the
--                        brand portal addresses it, e.g. "acme/acme-2026/3".
--                        The VERSION is part of it deliberately. A published
--                        version is immutable, so pinning one is what stops a
--                        later republish silently restyling a show that was
--                        signed off. It is also the only thing that can answer
--                        "which boards does this agreement touch" when a
--                        typeface licence lapses.
--
--   brand_style_item_id  RESOLUTION: the media_item holding this project's copy
--                        of style.json. The player needs a FILE, and it has no
--                        route from a portal address to one.
--
-- ⚠️ Why an item id rather than letting the player find the folder.
--
-- The delivered brand folder cannot survive a player's media cache: that cache
-- is a flat namespace keyed by deliverable file name, and its prune removes
-- every top-level entry the cartridge manifest does not list — a `brand/`
-- directory included. So brand files travel as ORDINARY MEDIA like everything
-- else, and the import rewrites style.json's `files` paths to the deliverable
-- names they were given. Then a player resolves faces through the manifest it
-- already holds, and the spec's folder stays what it was written to be: the
-- producer's layout, for portal storage and for the import to read.
--
-- Resolution order is session_set ?? project ?? the client's built-in default,
-- which is why both tables carry both columns.
--
-- Nullable and additive: every existing project and set is unbranded, which is
-- what they are today, and either peer ships independently.

ALTER TABLE project     ADD COLUMN brand_style         TEXT;
ALTER TABLE project     ADD COLUMN brand_style_item_id INTEGER REFERENCES media_item(id) ON DELETE SET NULL;
ALTER TABLE session_set ADD COLUMN brand_style         TEXT;
ALTER TABLE session_set ADD COLUMN brand_style_item_id INTEGER REFERENCES media_item(id) ON DELETE SET NULL;
