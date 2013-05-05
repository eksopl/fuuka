#!/usr/bin/perl

use strict;
use warnings;
use utf8;

# Use this to update your fuuka DB, when updating to SVN revision r183 or later.
#
# Recommended usage is:
# perl r0183.pl > r0183.mine.sql
# less r0183.mine.sql (to analyze the file)
# mysql -u <mysqluser> -p < r0183.mine.sql
#
# Hardcore usage:
# perl r0183.pl | mysql -u <mysqluser> -p
#
# There's also a static version in r0183.sql, if you don't want automatic
# generation for some reason.

BEGIN{-e "../board-config-local.pl" ?
    require "../board-config-local.pl" : require "../board-config.pl"}
    
my $boards = BOARD_SETTINGS;
my @boards = sort keys %$boards;
my $charset = DB_CHARSET;

print <<'HERE';
--
-- Run when upgrading to revision r183 or later
--

HERE

print 'USE ' . DB_DATABSE_NAME . ';';

for(@boards) {
	print <<"HERE";


--
-- Processing table `$_`
--

CREATE INDEX capcode_index ON `$_` (capcode);
HERE
}
