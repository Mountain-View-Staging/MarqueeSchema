ALTER TABLE project ADD COLUMN show_wallpaper_item_id INTEGER
  REFERENCES media_item(id) ON DELETE RESTRICT;

ALTER TABLE project ADD COLUMN desktop_wallpaper_item_id INTEGER
  REFERENCES media_item(id) ON DELETE RESTRICT;
