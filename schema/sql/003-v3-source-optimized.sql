ALTER TABLE media_file RENAME COLUMN file_name TO source_file_name;
ALTER TABLE media_file ADD COLUMN optimized_file_name TEXT;
CREATE UNIQUE INDEX idx_media_file_optimized ON media_file (optimized_file_name);
