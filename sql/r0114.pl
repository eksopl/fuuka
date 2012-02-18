#!/usr/bin/perl

use strict;
use warnings;
use utf8;

# Use this to update your fuuka DB, when updating to SVN revision r114 or later.
#
# Recommended usage is:
# perl r0114.pl > r0114.mine.sql
# less r0114.mine.sql (to analyze the file)
# mysql -u <mysqluser> -p < r0114.mine.sql
#
# Hardcore usage:
# perl r0114.pl | mysql -u <mysqluser> -p
#
# There's also a static version in r0114.sql, if you don't want automatic
# generation for some reason.

BEGIN{require "../board-config.pl"}

my $boards = BOARD_SETTINGS;
my @boards = sort keys %$boards;
my $charset = DB_CHARSET;

print <<'HERE';
--
-- Run when upgrading to revision r98 or later
--

HERE

print 'USE ' . DB_DATABSE_NAME . ';';

for(@boards) {
	print <<"HERE";


--
-- Updating table `$_`
--

-- Update with keys on: there's few NULL values to insert, the index will help
-- us only update those.
UPDATE `$_` SET name = NULL WHERE name = '';
UPDATE `$_` SET comment = NULL WHERE comment = '';

-- Update with keys off: a huge portion of all entries need to get updated, 
-- cost of a table scan + reenabling indexes beats the overhead of updating 
-- the indexes during updates.
ALTER TABLE `$_` DISABLE KEYS;

UPDATE `$_` SET media_hash = NULL WHERE media_hash = '';
UPDATE `$_` SET email = NULL WHERE email = '';
UPDATE `$_` SET trip = NULL WHERE trip = '';

-- Irrelevant: column doesn't have keys.
UPDATE `$_` SET preview = NULL WHERE preview = '';
UPDATE `$_` SET media = NULL WHERE media = '';
UPDATE `$_` SET media_filename = NULL WHERE media_filename = '';
UPDATE `$_` SET title = NULL WHERE title = '';
HERE
	print <<"HERE" if($_ eq 'a' or $_ eq 'jp');

-- Irrelevant: media_filename doesn't have keys and it's going to do a table 
-- scan regardless.
--
-- This query fixes an inconsistency in data left in very old, legacy
-- legacy versions o fuuka. Execute this query ONLY if you're running with /a/
-- or /jp/ tables acquired from Easymodo. Otherwise you're just wasting time.
UPDATE `$_` SET media_filename = CONCAT(SUBSTRING_INDEX(preview,'s.',1),
    SUBSTRING(media from -4)) WHERE (media_filename is NULL OR
    media_filename = '') AND preview != '' AND media != '';
HERE
	print <<"HERE";


-- Perform DB schema changes
--
-- Change the ID field to support IPv6
ALTER TABLE `$_` CHANGE id id DECIMAL(39, 0) UNSIGNED NOT NULL DEFAULT '0';

-- Adjust fields to new charset (utf8mb4) and new sizes
ALTER TABLE `$_` CHANGE preview preview VARCHAR(20) COLLATE $charset\_general_ci NULL DEFAULT NULL;
ALTER TABLE `$_` CHANGE media media TEXT COLLATE $charset\_general_ci NULL DEFAULT NULL;
ALTER TABLE `$_` CHANGE media_hash media_hash VARCHAR(25) COLLATE $charset\_general_ci NULL DEFAULT NULL;
ALTER TABLE `$_` CHANGE media_filename media_filename VARCHAR(20) COLLATE $charset\_general_ci NULL DEFAULT NULL;
ALTER TABLE `$_` CHANGE email email VARCHAR(100) COLLATE $charset\_general_ci NULL DEFAULT NULL;
ALTER TABLE `$_` CHANGE name name VARCHAR(100) COLLATE $charset\_general_ci NULL DEFAULT NULL;
ALTER TABLE `$_` CHANGE trip trip VARCHAR(25) COLLATE $charset\_general_ci NULL DEFAULT NULL;
ALTER TABLE `$_` CHANGE title title VARCHAR(100) COLLATE $charset\_general_ci NULL DEFAULT NULL;
ALTER TABLE `$_` CHANGE comment comment TEXT COLLATE $charset\_general_ci NULL DEFAULT NULL;
ALTER TABLE `$_` CHANGE delpass delpass TINYTEXT COLLATE $charset\_general_ci NULL DEFAULT NULL;

-- And the default charset for the table
ALTER TABLE `$_` COLLATE $charset\_general_ci;

-- Make numeric fields not null
ALTER TABLE `$_` CHANGE preview_w preview_w SMALLINT UNSIGNED NOT NULL DEFAULT '0';
ALTER TABLE `$_` CHANGE preview_h preview_h SMALLINT UNSIGNED NOT NULL DEFAULT '0';
ALTER TABLE `$_` CHANGE media_w media_w SMALLINT UNSIGNED NOT NULL DEFAULT '0';
ALTER TABLE `$_` CHANGE media_h media_h SMALLINT UNSIGNED NOT NULL DEFAULT '0';
ALTER TABLE `$_` CHANGE media_size media_size INT UNSIGNED NOT NULL DEFAULT '0';
ALTER TABLE `$_` CHANGE spoiler spoiler BOOL NOT NULL DEFAULT '0';
ALTER TABLE `$_` CHANGE deleted deleted BOOL NOT NULL DEFAULT '0';

-- Add sticky field
ALTER TABLE `$_` ADD sticky BOOL NOT NULL DEFAULT '0';

-- Re-enable keys.
ALTER TABLE `$_` ENABLE KEYS;

-- We can get rid of the _local tables, too.
DROP TABLE IF EXISTS `$_\_local`; 
HERE
}
