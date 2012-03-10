-- Run when upgrading to revision r142 or later
--
-- Replace `a` with `board`, where board is the name of the board you are 
-- archiving. Same for a_threads, update_thread_a, etc.
--
-- Copy and paste for every other board you have.
--
-- (There's too much to replace, so you might want to use the Perl script
-- instead, which will generate an .sql file for you)
--

USE archive;

--
-- Processing table `a`
--

DROP TABLE IF EXISTS `a_images`;

-- Creating images report table
CREATE TABLE `a_images` (
  `media_hash` varchar(25) NOT NULL,
  `num` int(10) unsigned NOT NULL,
  `subnum` int(10) unsigned NOT NULL,
  `parent` int(10) unsigned NOT NULL,
  `preview` varchar(20) NOT NULL,
  `total` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`media_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `a_daily`;

CREATE TABLE IF NOT EXISTS `a_daily` (
  `day` int(10) unsigned NOT NULL,
  `posts` int(10) unsigned NOT NULL,
  `images` int(10) unsigned NOT NULL,
  `sage` int(10) unsigned NOT NULL,
  `anons` int(10) unsigned NOT NULL,
  `trips` int(10) unsigned NOT NULL,
  `names` int(10) unsigned NOT NULL,
  PRIMARY KEY (`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `a_users`;

CREATE TABLE IF NOT EXISTS `a_users` (
  `name` varchar(100) NOT NULL DEFAULT '',
  `trip` varchar(25) NOT NULL DEFAULT '',
  `firstseen` int(11) NOT NULL,
  `postcount` int(11) NOT NULL,
  PRIMARY KEY (`name`, `trip`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- Creating stored procedures and updating triggers
DELIMITER //

DROP PROCEDURE IF EXISTS `insert_image_a`//

CREATE PROCEDURE `insert_image_a` (n_media_hash VARCHAR(25), n_num INT,
  n_subnum INT, n_parent INT, n_preview VARCHAR(20))
BEGIN
  DECLARE o_parent INT;
  
  -- This should be a transaction, but MySquirrel doesn't support transactions
  -- inside triggers or stored procedures (stay classy, MySQL)
  SELECT parent INTO o_parent FROM `a_images` WHERE media_hash = n_media_hash;
  IF o_parent IS NULL THEN
    INSERT INTO `a_images` VALUES (n_media_hash, n_num, n_subnum, n_parent,
      n_preview, 1);
  ELSEIF o_parent <> 0 AND n_parent = 0 THEN
    UPDATE `a_images` SET num = n_num, subnum = n_subnum, parent = n_parent,
      preview = n_preview, total = (total + 1) 
      WHERE media_hash = n_media_hash;
  ELSE
    UPDATE `a_images` SET total = (total + 1) WHERE 
      media_hash = n_media_hash;
  END IF;
END//

DROP PROCEDURE IF EXISTS `delete_image_a`//

CREATE PROCEDURE `delete_image_a` (n_media_hash VARCHAR(25))
BEGIN
  UPDATE `a_images` SET total = (total - 1) WHERE media_hash = n_media_hash;
END//

DROP PROCEDURE IF EXISTS `insert_post_a`//

CREATE PROCEDURE `insert_post_a` (p_timestamp INT, p_media_hash VARCHAR(25),
  p_email VARCHAR(100), p_name VARCHAR(100), p_trip VARCHAR(25))
BEGIN
  DECLARE d_day INT;
  DECLARE d_image INT;
  DECLARE d_sage INT;
  DECLARE d_anon INT;
  DECLARE d_trip INT;
  DECLARE d_name INT;
  
  SET d_day = FLOOR(p_timestamp/86400)*86400;
  SET d_image = p_media_hash IS NOT NULL;
  SET d_sage = COALESCE(p_email = 'sage', 0);
  SET d_anon = COALESCE(p_name = 'Anonymous' AND p_trip IS NULL, 0);
  SET d_trip = p_trip IS NOT NULL;
  SET d_name = COALESCE(p_name <> 'Anonymous' AND p_trip IS NULL, 1);
  
  INSERT INTO a_daily VALUES(d_day, 1, d_image, d_sage, d_anon, d_trip,
    d_name)
    ON DUPLICATE KEY UPDATE posts=posts+1, images=images+d_image,
    sage=sage+d_sage, anons=anons+d_anon, trips=trips+d_trip,
    names=names+d_name;
    
  -- Also should be a transaction. Lol MySQL.  
  IF (SELECT trip FROM a_users WHERE trip = p_trip) IS NOT NULL THEN
    UPDATE a_users SET postcount=postcount+1, 
      firstseen = LEAST(p_timestamp, firstseen)
      WHERE trip = p_trip;
  ELSE
    INSERT INTO a_users VALUES(COALESCE(p_name,''), COALESCE(p_trip,''), p_timestamp, 1)
    ON DUPLICATE KEY UPDATE postcount=postcount+1,
    firstseen = LEAST(VALUES(firstseen), firstseen);
  END IF;
END//

DROP PROCEDURE IF EXISTS `delete_post_a`//

CREATE PROCEDURE `delete_post_a` (p_timestamp INT, p_media_hash VARCHAR(25), p_email VARCHAR(100), p_name VARCHAR(100), p_trip VARCHAR(25))
BEGIN
  DECLARE d_day INT;
  DECLARE d_image INT;
  DECLARE d_sage INT;
  DECLARE d_anon INT;
  DECLARE d_trip INT;
  DECLARE d_name INT;
  
  SET d_day = FLOOR(p_timestamp/86400)*86400;
  SET d_image = p_media_hash IS NOT NULL;
  SET d_sage = COALESCE(p_email = 'sage', 0);
  SET d_anon = COALESCE(p_name = 'Anonymous' AND p_trip IS NULL, 0);
  SET d_trip = p_trip IS NOT NULL;
  SET d_name = COALESCE(p_name <> 'Anonymous' AND p_trip IS NULL, 1);
  
  UPDATE a_daily SET posts=posts-1, images=images-d_image,
    sage=sage-d_sage, anons=anons-d_anon, trips=trips-d_trip,
    names=names-d_name WHERE day = d_day;
  
  -- Also should be a transaction. Lol MySQL.
  IF (SELECT trip FROM a_users WHERE trip = p_trip) IS NOT NULL THEN
    UPDATE a_users SET postcount = postcount-1 WHERE trip = p_trip;  
  ELSE
    UPDATE a_users SET postcount = postcount-1 WHERE
      name = COALESCE(p_name, '') AND trip = COALESCE(p_trip, '');
  END IF;
END//

DROP TRIGGER IF EXISTS `after_ins_a`//

CREATE TRIGGER `after_ins_a` AFTER INSERT ON `a`
FOR EACH ROW
BEGIN
  IF NEW.parent = 0 THEN
    CALL create_thread_a(NEW.doc_id, NEW.num, NEW.timestamp);
  END IF;
  CALL update_thread_a(NEW.parent);
  CALL insert_post_a(NEW.timestamp, NEW.media_hash, NEW.email, NEW.name,
    NEW.trip);
  IF NEW.media_hash IS NOT NULL THEN
    CALL insert_image_a(NEW.media_hash, NEW.num, NEW.subnum, NEW.parent,
      NEW.preview);
  END IF;
END//

DROP TRIGGER IF EXISTS `after_del_a`//

CREATE TRIGGER `after_del_a` AFTER DELETE ON `a`
FOR EACH ROW
BEGIN
  CALL update_thread_a(OLD.parent);
  IF OLD.parent = 0 THEN
    CALL delete_thread_a(OLD.num);
  END IF;
  CALL delete_post_a(OLD.timestamp, OLD.media_hash, OLD.email, OLD.name, 
    OLD.trip);
  IF OLD.media_hash IS NOT NULL THEN
    CALL delete_image_a(OLD.media_hash);
  END IF;
END//

DELIMITER ;

--
-- Populating images table with image info
--
-- (About 7 minutes on /a/ with Easymodo data)
INSERT INTO `a_images` (
  SELECT media_hash, num, subnum, parent, preview, COUNT(*)
  FROM `a` WHERE parent = 0 AND media_hash IS NOT NULL AND preview IS NOT NULL
  GROUP BY media_hash
);

-- (About 14 minutes on /a/ with Easymodo data)
INSERT INTO `a_images` (
  SELECT media_hash, num, subnum, parent, preview, count(*) AS replyt
   FROM `a` WHERE parent <> 0 AND 
   media_hash IS NOT NULL AND preview IS NOT NULL GROUP BY media_hash
   )
ON DUPLICATE KEY UPDATE total = total + VALUES(total);

--
-- Populating daily report table with info
--
-- (About 6 minutes on /a/ with Easymodo data)
INSERT INTO `a_daily` (
  SELECT FLOOR(timestamp/86400)*86400 AS days, COUNT(*), 
    SUM(media_hash IS NOT NULL), SUM(COALESCE(email = 'sage', 0)),
    SUM(COALESCE(name = 'Anonymous' AND trip IS NULL, 0)), 
    SUM(trip IS NOT NULL), 
    SUM(COALESCE(name <> 'Anonymous' AND trip IS NULL, 1)) 
  FROM a GROUP BY days
);

--
-- Populating users table with users
--
-- (About 8 minutes on /a/ with Easymodo data)
INSERT INTO `a_users` (
  SELECT COALESCE(name, ''), '', MIN(timestamp), COUNT(*) from `a`
  WHERE trip IS NULL GROUP BY name 
);

-- (About 6 minutes on /a/ with Easymodo data)
INSERT INTO `a_users` (
  SELECT COALESCE(name, ''), trip, MIN(timestamp), COUNT(*) from `a`
  WHERE trip IS NOT NULL GROUP BY trip 
);

-- Add the remaining indexes
CREATE INDEX total_index ON `a_images` (total);
CREATE INDEX firstseen_index ON `a_users` (firstseen);
CREATE INDEX postcount_index ON `a_users` (postcount);
