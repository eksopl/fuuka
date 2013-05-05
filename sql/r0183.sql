-- Run when upgrading to revision r183 or later
--
--
-- Replace `a` with `board`, where board is the name of the board you are 
-- archiving. Copy and paste for every other board you have.
--

--
-- Processing table `a`
--

CREATE INDEX capcode_index ON `a` (capcode);
