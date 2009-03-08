#!perl

#
# General
#

# list of boards you'll be archiving
use constant BOARD_SETTINGS			=> {
#	a => {
#		name					=> "Anime & Manga", # Name, as it will appear on web page
#		
#		pages					=> [[[0],15],[[1..10],7200]],
#													# Each element of a list is processed in own thread.
#													# Each element is a list with two elements
#													#      first: list of pages to check periodically, e.g. [0,1,2]
#													#      second: how long to sleep in seconds after checking all of them
#		
#		"thread-refresh-rate"	=> 16,				# Time, in minutes, for how long to wait before updating thread. 
#		
#													# How many requests should be carried out simultaneously to:
#		"new-thread-threads"	=> 6,				#     get new threads and refresh old ones
#		"thumb-threads"			=> 6,				#     get thumbs
#		"media-threads"			=> 0,				#     get pictures
#		
#		link					=> "http://zip.4chan.org/a",
#	},
#	jp => {
#		name					=> "Japan/General",
#		pages					=> [[[0],30],[[1..10],7200]],
#		"thread-refresh-rate"	=> 12,
#		"new-thread-threads"	=> 3,
#		"thumb-threads"			=> 3,
#		
#		link					=> "http://zip.4chan.org/jp",
#	},
	t => {
		name					=> "Torrents",
		pages					=> [[[0..10],3600]],
		"thread-refresh-rate"	=> 120,
		"new-thread-threads"	=> 3,
		"thumb-threads"			=> 3,
		
		link					=> "http://cgi.4chan.org/t",
	},
	hr => {
		name					=> "High Resolution",
		pages					=> [[[0],240],[[0..10],3600]],
		"thread-refresh-rate"	=> 120,
		"new-thread-threads"	=> 3,
		"thumb-threads"			=>  12,
		"media-threads"			=> 4,
		
		link					=> "http://orz.4chan.org/hr",
	},
#	b => {
#		name					=> "Random",
#		pages					=> [[[0],0],[[1],0],[[2],0],[[3],0]],
#		"thread-refresh-rate"	=> 120,
#		"new-thread-threads"	=> 10,
#		"thumb-threads"			=> 10,
#		
#		link					=> "http://img.4chan.org/b",
#	},

};

# where to put images and thumbs from archived boards
use constant IMAGES_LOCATION		=> "f:/board";
use constant IMAGES_LOCATION_HTTP	=> "/board";

# where your files with reports located
use constant REPORTS_LOCATION		=> "b:/server-data/board/reports";

# where all web files (pictures, js, css, etc.) are located
use constant MEDIA_LOCATION_HTTP	=> "/media";

# how to run the program for plotting
use constant GNUPLOT				=> 'wgnuplot';

#
# Database
#

# it's ok to leave this empty
use constant DB_CONNECTION_STRING	=> "";

# these will be used to construct connection string if you leave it empty,
# and will be ignored if you provide connection string)
use constant DB_HOST					=> "localhost";
use constant DB_DATABSE_NAME			=> "Yotsuba";

use constant DB_USERNAME				=> "root";
use constant DB_PASSWORD				=> "qwerty";

#
# Posting
#

# Password to actually delete files and not just put a a trash bin icon next to them.
use constant DELPASS					=> 'TOPSECRET';				

# Cryptographic secret. It's okay to leave this unchanged, not like anyone cares.
use constant SECRET						=> 'TOPSECRET';				

# Maximum number of characters in subject, name, and email
use constant MAX_FIELD_LENGTH			=> 100;

# Maximum number of characters in a comment
use constant MAX_COMMENT_LENGTH			=> 2048;

# Maximum number of lines in a comment
use constant MAX_COMMENT_LINES			=> 40;


# Seconds between posts (floodcheck)
use constant RENZOKU => 5;

# Seconds between identical posts (floodcheck)
use constant RENZOKU3 => 900;


#
# that's it folks, move along, nothing to see here.
# I am putting code into config file
#

use constant SPAWNER => sub{my $board_name=shift;Board::Mysql->new($board_name,
	connstr			=> DB_CONNECTION_STRING,
	host			=> DB_HOST,
	database		=> DB_DATABSE_NAME,
	name			=> DB_USERNAME,
	password		=> DB_PASSWORD,
	images			=> IMAGES_LOCATION,
	create			=> 1,
	full_pictures	=> BOARD_SETTINGS->{$board_name}->{"media-threads"}?1:0,
) or die "Couldn't use mysql board with table $board_name"};

sub yotsutime(){time-5*60*60}

1;
