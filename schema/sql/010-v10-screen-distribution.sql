ALTER TABLE screen_config ADD COLUMN screen_id TEXT;

ALTER TABLE screen_config ADD COLUMN published_revision INTEGER;
ALTER TABLE screen_config ADD COLUMN published_at       INTEGER;

ALTER TABLE screen_code RENAME TO screen_location;
ALTER TABLE screen_location RENAME COLUMN code TO location_id;
