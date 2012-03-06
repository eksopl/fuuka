#!/usr/bin/perl

use strict;
use warnings;
use utf8;

# Use this to update your fuuka DB, when updating to SVN revision r142 or later.
#
# Recommended usage is:
# perl r0142_2.pl > r0142_2.mine.sql
# less r0142_2.mine.sql (to analyze the file)
# mysql -u <mysqluser> -p < r0142_2.mine.sql
#
# Hardcore usage:
# perl r0142_2.pl | mysql -u <mysqluser> -p
#
# There's also a static version in r0142.sql, if you don't want automatic
# generation for some reason.

BEGIN{-e "../board-config-local.pl" ?
    require "../board-config-local.pl" : require "../board-config.pl"}
    
my $boards = BOARD_SETTINGS;
my @boards = sort keys %$boards;
my $charset = DB_CHARSET;

print <<'HERE';
--
-- Run when upgrading to revision r142 or later
--

HERE

print 'USE ' . DB_DATABSE_NAME . ';';

for(@boards) {
	print <<"HERE";


--
-- Processing table `$_`
--

DROP TABLE IF EXISTS `$_\_images`;

-- Creating images report table
CREATE TABLE `$_\_images` (
  `media_hash` varchar(25) NOT NULL,
  `num` int(10) unsigned NOT NULL,
  `subnum` int(10) unsigned NOT NULL,
  `parent` int(10) unsigned NOT NULL,
  `preview` varchar(20) NOT NULL,
  `total` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`media_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- Creating stored procedures and updating triggers
DELIMITER //

DROP PROCEDURE IF EXISTS `insert_image_$_`//

CREATE PROCEDURE `insert_image_$_` (n_media_hash VARCHAR(25), n_num INT,
  n_subnum INT, n_parent INT, n_preview VARCHAR(20))
BEGIN
  DECLARE o_parent INT;
  -- This should be a transaction, but MySquirrel doesn't support transactions
  -- inside triggers or stored procedures (stay classy, MySQL)
  SELECT parent INTO o_parent FROM `$_\_images` WHERE media_hash = n_media_hash;
  IF o_parent IS NULL THEN
    INSERT INTO `$_\_images` VALUES (n_media_hash, n_num, n_subnum, n_parent,
      n_preview, 1);
  ELSEIF o_parent != 0 AND n_parent = 0 THEN
    UPDATE `$_\_images` SET num = n_num, subnum = n_subnum, parent = n_parent,
      preview = n_preview, total = (total + 1) 
      WHERE media_hash = n_media_hash;
  ELSE
    UPDATE `$_\_images` SET total = (total + 1) WHERE 
      media_hash = n_media_hash;
  END IF;
END//

DROP PROCEDURE IF EXISTS `delete_image_$_`//

CREATE PROCEDURE `delete_image_$_` (n_media_hash VARCHAR(25))
BEGIN
  UPDATE `$_\_images` SET total = (total - 1) WHERE media_hash = n_media_hash;
END//

DROP TRIGGER IF EXISTS `after_ins_$_`//

CREATE TRIGGER `after_ins_$_` AFTER INSERT ON `$_`
FOR EACH ROW
BEGIN
  IF NEW.parent = 0 THEN
    CALL create_thread_$_(NEW.doc_id, NEW.num, NEW.timestamp);
  END IF;
  CALL update_thread_$_(NEW.parent);
  IF NEW.media_hash IS NOT NULL THEN
    CALL insert_image_$_(NEW.media_hash, NEW.num, NEW.subnum, NEW.parent,
      NEW.preview);
  END IF;
END;
//

DROP TRIGGER IF EXISTS `after_del_$_`//

CREATE TRIGGER `after_del_$_` AFTER DELETE ON `$_`
FOR EACH ROW
BEGIN
  CALL update_thread_$_(OLD.parent);
  IF OLD.parent = 0 THEN
    CALL delete_thread_$_(OLD.num);
  END IF;
  IF OLD.media_hash IS NOT NULL THEN
    CALL delete_image_$_(OLD.media_hash);
  END IF;
END;
//

DELIMITER ;

-- Populating images table with image info
INSERT INTO `$_\_images` (
  SELECT media_hash, num, subnum, parent, preview, total FROM `$_` JOIN 
  (SELECT hash, total, MAX(preview_w) AS w FROM `$_` JOIN 
    (SELECT media_hash as hash, COUNT(media_hash) AS total FROM `$_` GROUP BY
      media_hash) AS x ON media_hash=hash GROUP BY media_hash) AS x 
  ON media_hash=hash AND preview_w=w GROUP BY media_hash ORDER BY total DESC
);

-- Add the remaining indexes
CREATE INDEX total_index ON `$_\_images` (total);
HERE
}
