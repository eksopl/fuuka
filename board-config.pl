#!perl

#
# General
#

# list of boards you'll be archiving
use constant BOARD_SETTINGS         => {
#    a => {
#        name                    => "Anime & Manga", # Name, as it will appear on web page
#        
#        pages                   => [[[0],15],[[1..15],7200]],
#                                                    # Each element of a list is processed in own thread.
#                                                    # Each element is a list with two elements
#                                                    #      first: list of pages to check periodically, e.g. [0,1,2]
#                                                    #      second: how long to sleep in seconds after checking all of them
#        
#        "thread-refresh-rate"   => 16,              # Time, in minutes, for how long to wait before updating thread. 
#        
#                                                    # How many requests should be carried out simultaneously to:
#        "new-thread-threads"    => 6,               #     get new threads and refresh old ones
#        "thumb-threads"         => 6,               #     get thumbs
#        "media-threads"         => 0,               #     get pictures
#        
#        link                    => "http://boards.4chan.org/a",
#        img_link                => "http://images.4chan.org/a",
#        "database"              => "Mysql",
#    },
#    jp => {
#        name                    => "Otaku Culture",
#        pages                   => [[[0],30],[[1..15],7200]],
#        "thread-refresh-rate"   => 12,
#        "new-thread-threads"    => 3,
#        "thumb-threads"         => 3,
#        "media-threads"         => 0,
#        
#        link                    => "http://boards.4chan.org/jp",
#		img_link                => "http://images.4chan.org/jp",
#        "database"              => "Mysql",
#    },
#   hr => {
#       name                    => "High Resolution",
#       pages                   => [[[0],240],[[0..10],3600]],
#       "thread-refresh-rate"   => 120,
#       "new-thread-threads"    => 3,
#       "thumb-threads"         =>  12,
#       "media-threads"         => 4,
#       
#       link                    => "http://boards.4chan.org/hr",
#   },
#   b => {
#       name                    => "Random",
#       pages                   => [[[0],0],[[1],0],[[2],0],[[3],0]],
#       "thread-refresh-rate"   => 120,
#       "new-thread-threads"    => 10,
#       "thumb-threads"         => 10,
#       
#       link                    => "http://img.4chan.org/b",
#   },
#   e => {
#       name                    => "Ecchi",
#       pages                   => [[[0],240],[[0..10],3600]],
#       "thread-refresh-rate"   => 120,
#       "new-thread-threads"    => 3,
#       "thumb-threads"         =>  12,
#       "media-threads"         => 4,
       
#       link                    => "http://boards.4chan.org/e",
#   },


};

# where to put images and thumbs from archived boards
use constant IMAGES_LOCATION        => "f:/board";
use constant IMAGES_LOCATION_HTTP   => "/board";

# where your files with reports located
use constant REPORTS_LOCATION       => "b:/server-data/board/reports";

# where all web files (pictures, js, css, etc.) are located
use constant MEDIA_LOCATION_HTTP    => "/media";

# how to run the program for plotting
use constant GNUPLOT                => 'wgnuplot';

# path to script, relative to HTTP root. Use together with mod_rewrite rules
use constant LOCATION_HTTP          => $ENV{SCRIPT_NAME}

# terminal type for gnuplot. If you have gnuplot 4.4+ compiled with cairo
# support, switch this to pngcairo for prettier graphs.
use constant GNUPLOT_TERMINAL       => 'png';

#
# Database
#

# it's ok to leave this empty
use constant DB_CONNECTION_STRING   => "";

# these will be used to construct connection string if you leave it empty,
# and will be ignored if you provide connection string)
use constant DB_HOST                    => "localhost";
use constant DB_DATABSE_NAME            => "Yotsuba";

use constant DB_USERNAME                => "root";
use constant DB_PASSWORD                => "qwerty";

#
# Posting
#

# Password to actually delete files and not just put a a trash bin icon next to them.
use constant DELPASS                    => 'TOPSECRET';              

# Password to delete images
use constant IMGDELPASS                 => 'TOPSECRET2';

# Cryptographic secret encoded in base 64, used for secure tripcodes. 
# Default is world4chan's (dis.4chan.org) former secret.
use constant SECRET						=> '
FW6I5Es311r2JV6EJSnrR2+hw37jIfGI0FB0XU5+9lua9iCCrwgkZDVRZ+1PuClqC+78FiA6hhhX
U1oq6OyFx/MWYx6tKsYeSA8cAs969NNMQ98SzdLFD7ZifHFreNdrfub3xNQBU21rknftdESFRTUr
44nqCZ0wyzVVDySGUZkbtyHhnj+cknbZqDu/wjhX/HjSitRbtotpozhF4C9F+MoQCr3LgKg+CiYH
s3Phd3xk6UC2BG2EU83PignJMOCfxzA02gpVHuwy3sx7hX4yvOYBvo0kCsk7B5DURBaNWH0srWz4
MpXRcDletGGCeKOz9Hn1WXJu78ZdxC58VDl20UIT9er5QLnWiF1giIGQXQMqBB+Rd48/suEWAOH2
H9WYimTJWTrK397HMWepK6LJaUB5GdIk56ZAULjgZB29qx8Cl+1K0JWQ0SI5LrdjgyZZUTX8LB/6
Coix9e6+3c05Pk6Bi1GWsMWcJUf7rL9tpsxROtq0AAQBPQ0rTlstFEziwm3vRaTZvPRboQfREta0
9VA+tRiWfN3XP+1bbMS9exKacGLMxR/bmO5A57AgQF+bPjhif5M/OOJ6J/76q0JDHA==';			

# Maximum number of characters in subject, name, and email
use constant MAX_FIELD_LENGTH           => 100;

# Maximum number of characters in a comment
use constant MAX_COMMENT_LENGTH			=> 4096;

# Maximum number of lines in a comment
use constant MAX_COMMENT_LINES          => 40;


# Seconds between posts (floodcheck)
use constant RENZOKU => 5;

# Seconds between identical posts (floodcheck)
use constant RENZOKU3 => 900;

# Set to 1 to enable the sage feature in ghost posts
use constant ENABLE_SAGE => 0;

#
# that's it folks, move along, nothing to see here.
# I am putting code into config file
#

use constant SPAWNER => sub{my $board_name=shift;
    my $board_engine = "Board::".(BOARD_SETTINGS->{$board_name}->{"database"} or 'Mysql');
    $board_engine->new($board_name,
    connstr         => DB_CONNECTION_STRING,
    host            => DB_HOST,
    database        => DB_DATABSE_NAME,
    name            => DB_USERNAME,
    password        => DB_PASSWORD,
    images          => IMAGES_LOCATION,
    create          => 1,
    full_pictures   => BOARD_SETTINGS->{$board_name}->{"media-threads"}?1:0,
) or die "Couldn't use mysql board with table $board_name"};

sub yotsutime(){
	use DateTime;
	use DateTime::TimeZone;
	time+DateTime::TimeZone->new(name => 'America/New_York')->offset_for_datetime(DateTime->now())
}

1;
