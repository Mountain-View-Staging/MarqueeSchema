ALTER TABLE playlist_entry
  ADD COLUMN resource_type TEXT NOT NULL DEFAULT 'media_item';
