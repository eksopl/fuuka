-- Run when upgrading to revision r114 or later
--
-- Replace `a` with `board`, where board is the name of the board you are 
-- archiving. Copy and paste for every other board you have.
--

-- Update with keys on: there's few NULL values to insert, the index will help
-- us only update those.
UPDATE `a` SET name = NULL WHERE name = '';
UPDATE `a` SET comment = NULL WHERE comment = '';

-- Update with keys off: a huge portion of all entries need to get updated, 
-- cost of a table scan + reenabling indexes beats the overhead of updating 
-- the indexes during updates.
ALTER TABLE `a` DISABLE KEYS;

UPDATE `a` SET media_hash = NULL WHERE media_hash = '';
UPDATE `a` SET email = NULL WHERE email = '';
UPDATE `a` SET trip = NULL WHERE trip = '';

-- Irrelevant: column doesn't have keys.
UPDATE `a` SET preview = NULL WHERE preview = '';
UPDATE `a` SET media = NULL WHERE media = '';
UPDATE `a` SET media_filename = NULL WHERE media_filename = '';
UPDATE `a` SET title = NULL WHERE title = '';

-- Irrelevant: media_filename doesn't have keys and it's going to do a table 
-- scan regardless.
--
-- This query fixes an inconsistency in data left in very old, legacy
-- legacy versions o fuuka. Execute this query ONLY if you're running with /a/
-- or /jp/ tables acquired from Easymodo. Otherwise you're just wasting time.
UPDATE `a` SET media_filename = CONCAT(SUBSTRING_INDEX(preview,'s.',1),
	SUBSTRING(media from -4)) WHERE (media_filename is NULL OR
	media_filename = '') AND preview != '' AND media != '';

-- Perform DB schema changes
--
-- Adjust fields to new charset (utf8mb4) and new sizes
-- utf8mb4 requires MySQL 5.5 or later. Upgrade or change it to utf8mb4_general_ci.
-- See DB_CHARSET in board-config.pl for more info.
-- Perform DB schema changes
--
-- Adjust fields and table default charset to the to new one (utf8mb4).
-- Adjust sizes and types as well.
-- Change the ID field to support IPv6.
-- Make numeric fields not null.
-- Add sticky field.
ALTER TABLE `a` COLLATE utf8mb4_general_ci,
CHANGE preview preview VARCHAR(20) COLLATE utf8mb4_general_ci NULL DEFAULT NULL,
CHANGE media media TEXT COLLATE utf8mb4_general_ci NULL DEFAULT NULL,
CHANGE media_hash media_hash VARCHAR(25) COLLATE utf8mb4_general_ci NULL DEFAULT NULL,
CHANGE media_filename media_filename VARCHAR(20) COLLATE utf8mb4_general_ci NULL DEFAULT NULL,
CHANGE email email VARCHAR(100) COLLATE utf8mb4_general_ci NULL DEFAULT NULL,
CHANGE name name VARCHAR(100) COLLATE utf8mb4_general_ci NULL DEFAULT NULL,
CHANGE trip trip VARCHAR(25) COLLATE utf8mb4_general_ci NULL DEFAULT NULL,
CHANGE title title VARCHAR(100) COLLATE utf8mb4_general_ci NULL DEFAULT NULL,
CHANGE comment comment TEXT COLLATE utf8mb4_general_ci NULL DEFAULT NULL,
CHANGE delpass delpass TINYTEXT COLLATE utf8mb4_general_ci NULL DEFAULT NULL,
CHANGE id id DECIMAL(39, 0) UNSIGNED NOT NULL DEFAULT '0',
CHANGE preview_w preview_w SMALLINT UNSIGNED NOT NULL DEFAULT '0',
CHANGE preview_h preview_h SMALLINT UNSIGNED NOT NULL DEFAULT '0',
CHANGE media_w media_w SMALLINT UNSIGNED NOT NULL DEFAULT '0',
CHANGE media_h media_h SMALLINT UNSIGNED NOT NULL DEFAULT '0',
CHANGE media_size media_size INT UNSIGNED NOT NULL DEFAULT '0',
CHANGE spoiler spoiler BOOL NOT NULL DEFAULT '0',
CHANGE deleted deleted BOOL NOT NULL DEFAULT '0',
ADD sticky BOOL NOT NULL DEFAULT '0';

-- Re-enable keys.
ALTER TABLE `a` ENABLE KEYS;

-- We can get rid of the _local tables, too.
DROP TABLE IF EXISTS `a_local`;
