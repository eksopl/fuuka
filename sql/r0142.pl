#!/usr/bin/perl

use strict;
use warnings;
use utf8;

# Use this to update your fuuka DB, when updating to SVN revision r142 or later.
#
# Recommended usage is:
# perl r0142.pl > r0142.mine.sql
# less r0142.mine.sql (to analyze the file)
# mysql -u <mysqluser> -p < r0142.mine.sql
#
# Hardcore usage:
# perl r0142.pl | mysql -u <mysqluser> -p
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

-- Creating threads table
CREATE TABLE IF NOT EXISTS `$_\_threads` (
  `doc_id_p` int unsigned NOT NULL,
  `parent` int unsigned NOT NULL,
  `time_op` int unsigned NOT NULL,
  `time_last` int unsigned NOT NULL,
  `time_bump` int unsigned NOT NULL,
  `time_ghost` int unsigned DEFAULT NULL,
  `time_ghost_bump` int unsigned DEFAULT NULL,
  `nreplies` int unsigned NOT NULL DEFAULT '0',
  `nimages` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`doc_id_p`)
) ENGINE=InnoDB;

TRUNCATE TABLE `$_\_threads`;

-- Populating threads table with threads
INSERT INTO `$_\_threads` (
  SELECT
    op.doc_id_p, op.p, op.timestamp, 0, 0, NULL, NULL, 0, 0
  FROM
    (SELECT doc_id AS doc_id_p, num AS p, timestamp FROM `$_` WHERE parent = 0)
    AS op
);

-- Updating threads with reply information
UPDATE
  `$_\_threads` op
SET
  op.time_last = (
    COALESCE(GREATEST(
      op.time_op,
      (SELECT MAX(timestamp) FROM `$_` re FORCE INDEX(parent_index) WHERE 
        re.parent = op.parent GROUP BY parent)
    ), op.time_op)
  ),
  op.time_bump = (
    COALESCE(GREATEST(
      op.time_op,
      (SELECT MAX(timestamp) FROM `$_` re FORCE INDEX(parent_index) WHERE
        re.parent = op.parent AND (re.email <> 'sage' OR re.email IS NULL)
        GROUP BY parent)
    ), op.time_op)
  ),
  op.time_ghost = (
    SELECT MAX(timestamp) FROM `$_` re FORCE INDEX(parent_index) WHERE 
      re.parent = op.parent AND re.subnum <> 0 GROUP BY parent
  ),
  op.time_ghost_bump = (
    SELECT MAX(timestamp) FROM `$_` re FORCE INDEX(parent_index) WHERE
      re.parent = op.parent AND re.subnum <> 0 AND (re.email <> 'sage'
        OR re.email IS NULL) GROUP BY parent
  ),
  op.nreplies = (
    SELECT COUNT(*) FROM `$_` re FORCE INDEX(parent_index) WHERE
      re.parent = op.parent
  ),
  op.nimages = (
    SELECT COUNT(media_hash) FROM `$_` re FORCE INDEX(parent_index) WHERE
      re.parent = op.parent
);

-- Creating triggers and stored procedures
DELIMITER //

DROP PROCEDURE IF EXISTS `update_thread_$_`// 

CREATE PROCEDURE `update_thread_$_` (tnum INT) 
BEGIN 
  UPDATE
    `$_\_threads` op
  SET
    op.time_last = (
      COALESCE(GREATEST(
        op.time_op,
        (SELECT MAX(timestamp) FROM `$_` re FORCE INDEX(parent_index) WHERE
          re.parent = tnum AND re.subnum = 0)
        ), op.time_op)
      ),
      op.time_bump = (
        COALESCE(GREATEST(
          op.time_op,
          (SELECT MAX(timestamp) FROM `$_` re FORCE INDEX(parent_index) WHERE
            re.parent = tnum AND (re.email <> 'sage' OR re.email IS NULL)
            AND re.subnum = 0)
        ), op.time_op)
      ),
      op.time_ghost = (
        SELECT MAX(timestamp) FROM `$_` re FORCE INDEX(parent_index) WHERE 
          re.parent = tnum AND re.subnum <> 0
      ),
      op.time_ghost_bump = (
        SELECT MAX(timestamp) FROM `$_` re FORCE INDEX(parent_index) WHERE
          re.parent = tnum AND re.subnum <> 0 AND (re.email <> 'sage' OR 
            re.email IS NULL)
      ),
      op.nreplies = (
        SELECT COUNT(*) FROM `$_` re FORCE INDEX(parent_index) WHERE 
          re.parent = tnum
      ),
      op.nimages = (
        SELECT COUNT(media_hash) FROM `$_` re FORCE INDEX(parent_index) WHERE 
          re.parent = tnum
      )
    WHERE op.parent = tnum;
END//

DROP PROCEDURE IF EXISTS `create_thread_$_`// 

CREATE PROCEDURE `create_thread_$_` (doc_id INT, num INT, timestamp INT) 
BEGIN
  INSERT IGNORE INTO `$_\_threads` VALUES (doc_id, num, timestamp, timestamp,
    timestamp, NULL, NULL, 0, 0);
END//

DROP PROCEDURE IF EXISTS `delete_thread_$_`// 

CREATE PROCEDURE `delete_thread_$_` (tnum INT) 
BEGIN
  DELETE FROM `$_\_threads` WHERE parent = tnum;
END//

DROP TRIGGER IF EXISTS `after_ins_$_`// 

CREATE TRIGGER `after_ins_$_` AFTER INSERT ON `$_`
FOR EACH ROW
BEGIN
  IF NEW.parent = 0 THEN
    CALL create_thread_$_(NEW.doc_id, NEW.num, NEW.timestamp);
  END IF;
  CALL update_thread_$_(NEW.parent);
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
END;
//

DELIMITER ;
HERE
}
