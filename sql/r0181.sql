-- Run when upgrading to revision r181 or later
--
--
-- Replace `a` with `board`, where board is the name of the board you are 
-- archiving. Copy and paste for every other board you have.
--

--
-- Processing table `a`
--

ALTER TABLE `a` CHANGE `capcode` `capcode` VARCHAR(1) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL DEFAULT 'N';
CREATE INDEX media_index ON `a` (media_filename);
