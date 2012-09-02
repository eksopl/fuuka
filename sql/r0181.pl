#!/usr/bin/perl

use strict;
use warnings;
use utf8;

# Use this to update your fuuka DB, when updating to SVN revision r181 or later.
#
# Recommended usage is:
# perl r0181.pl > r0181.mine.sql
# less r0181.mine.sql (to analyze the file)
# mysql -u <mysqluser> -p < r0181.mine.sql
#
# Hardcore usage:
# perl r0181.pl | mysql -u <mysqluser> -p
#
# There's also a static version in r0181.sql, if you don't want automatic
# generation for some reason.

BEGIN{-e "../board-config-local.pl" ?
    require "../board-config-local.pl" : require "../board-config.pl"}
    
my $boards = BOARD_SETTINGS;
my @boards = sort keys %$boards;
my $charset = DB_CHARSET;

print <<'HERE';
--
-- Run when upgrading to revision r181 or later
--

HERE

print 'USE ' . DB_DATABSE_NAME . ';';

for(@boards) {
	print <<"HERE";


--
-- Processing table `$_`
--

ALTER TABLE `$_` CHANGE `capcode` `capcode` VARCHAR(1) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL DEFAULT 'N';
CREATE INDEX media_index ON `$_` (media_filename);
HERE
}
