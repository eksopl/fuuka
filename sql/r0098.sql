-- Run when upgrading to revision r98 or later
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

-- Change the ID field to support IPv6
ALTER TABLE  `a` CHANGE id id DECIMAL(39, 0) UNSIGNED NOT NULL DEFAULT '0';

-- Re-enable keys.
ALTER TABLE `a` ENABLE KEYS;

-- We can get rid of the _local tables, too.
DROP TABLE IF EXISTS `a_local`;
