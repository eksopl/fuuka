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


--
-- Processing table `a`
--

DROP TABLE IF EXISTS `a_threads`;

-- Creating threads table
CREATE TABLE IF NOT EXISTS `a_threads` (
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
) ENGINE=InnoDB COLLATE utf8_general_ci;

-- Populating threads table with threads
INSERT INTO `a_threads` (
  SELECT
    op.doc_id_p, op.p, op.timestamp, 0, 0, NULL, NULL, 0, 0
  FROM
    (SELECT doc_id AS doc_id_p, num AS p, timestamp FROM `a` WHERE parent = 0)
    AS op
);

-- Updating threads with reply information
UPDATE
  `a_threads` op
SET
  op.time_last = (
    COALESCE(GREATEST(
      op.time_op,
      (SELECT MAX(timestamp) FROM `a` re FORCE INDEX(parent_index) WHERE 
        re.parent = op.parent GROUP BY parent)
    ), op.time_op)
  ),
  op.time_bump = (
    COALESCE(GREATEST(
      op.time_op,
      (SELECT MAX(timestamp) FROM `a` re FORCE INDEX(parent_index) WHERE
        re.parent = op.parent AND (re.email <> 'sage' OR re.email IS NULL)
        GROUP BY parent)
    ), op.time_op)
  ),
  op.time_ghost = (
    SELECT MAX(timestamp) FROM `a` re FORCE INDEX(parent_index) WHERE 
      re.parent = op.parent AND re.subnum <> 0 GROUP BY parent
  ),
  op.time_ghost_bump = (
    SELECT MAX(timestamp) FROM `a` re FORCE INDEX(parent_index) WHERE
      re.parent = op.parent AND re.subnum <> 0 AND (re.email <> 'sage'
        OR re.email IS NULL) GROUP BY parent
  ),
  op.nreplies = (
    SELECT COUNT(*) FROM `a` re FORCE INDEX(parent_index) WHERE
      re.parent = op.parent
  ),
  op.nimages = (
    SELECT COUNT(media_hash) FROM `a` re FORCE INDEX(parent_index) WHERE
      re.parent = op.parent
);

-- Creating triggers and stored procedures
DELIMITER //

DROP PROCEDURE IF EXISTS `update_thread_a`// 

CREATE PROCEDURE `update_thread_a` (tnum INT) 
BEGIN 
  UPDATE
    `a_threads` op
  SET
    op.time_last = (
      COALESCE(GREATEST(
        op.time_op,
        (SELECT MAX(timestamp) FROM `a` re FORCE INDEX(parent_index) WHERE
          re.parent = tnum AND re.subnum = 0)
        ), op.time_op)
      ),
      op.time_bump = (
        COALESCE(GREATEST(
          op.time_op,
          (SELECT MAX(timestamp) FROM `a` re FORCE INDEX(parent_index) WHERE
            re.parent = tnum AND (re.email <> 'sage' OR re.email IS NULL)
            AND re.subnum = 0)
        ), op.time_op)
      ),
      op.time_ghost = (
        SELECT MAX(timestamp) FROM `a` re FORCE INDEX(parent_index) WHERE 
          re.parent = tnum AND re.subnum <> 0
      ),
      op.time_ghost_bump = (
        SELECT MAX(timestamp) FROM `a` re FORCE INDEX(parent_index) WHERE
          re.parent = tnum AND re.subnum <> 0 AND (re.email <> 'sage' OR 
            re.email IS NULL)
      ),
      op.nreplies = (
        SELECT COUNT(*) FROM `a` re FORCE INDEX(parent_index) WHERE 
          re.parent = tnum
      ),
      op.nimages = (
        SELECT COUNT(media_hash) FROM `a` re FORCE INDEX(parent_index) WHERE 
          re.parent = tnum
      )
    WHERE op.parent = tnum;
END//

DROP PROCEDURE IF EXISTS `create_thread_a`// 

CREATE PROCEDURE `create_thread_a` (doc_id INT, num INT, timestamp INT) 
BEGIN
  INSERT IGNORE INTO `a_threads` VALUES (doc_id, num, timestamp, timestamp,
    timestamp, NULL, NULL, 0, 0);
END//

DROP PROCEDURE IF EXISTS `delete_thread_a`// 

CREATE PROCEDURE `delete_thread_a` (tnum INT) 
BEGIN
  DELETE FROM `a_threads` WHERE parent = tnum;
END//

DROP TRIGGER IF EXISTS `after_ins_a`// 

CREATE TRIGGER `after_ins_a` AFTER INSERT ON `a`
FOR EACH ROW
BEGIN
  IF NEW.parent = 0 THEN
    CALL create_thread_a(NEW.doc_id, NEW.num, NEW.timestamp);
  END IF;
  CALL update_thread_a(NEW.parent);
END;
//

DROP TRIGGER IF EXISTS `after_del_a`// 

CREATE TRIGGER `after_del_a` AFTER DELETE ON `a`
FOR EACH ROW
BEGIN
  CALL update_thread_a(OLD.parent);
  IF OLD.parent = 0 THEN
    CALL delete_thread_a(OLD.num);
  END IF;
END;
//

DELIMITER ;

-- Add the remaining indexes
CREATE INDEX parent_index ON `a_threads` (parent);
CREATE INDEX time_ghost_bump_index ON `a_threads` (time_ghost_bump);
