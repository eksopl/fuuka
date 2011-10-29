-- Run when upgrading to revision r70

CREATE TABLE IF NOT EXISTS `index_counters` (
  `id` varchar(50) NOT NULL,
  `val` int(10) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- For the following three lines:
-- Replace `a` with `board`, where board is the name of the board you are archiving
-- Copy and paste for every other board you have

alter table `a` drop primary key;
alter table `a` add doc_id int(10) unsigned not null auto_increment primary key first;
alter ignore table `a` add unique num_subnum_index (num, subnum);
