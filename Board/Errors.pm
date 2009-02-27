package Board::Errors;

use strict;
use warnings;

require Exporter;
our @ISA=qw/Exporter/;
our @EXPORT=qw/ALL_OK TRY_AGAIN FORGET_IT NONEXIST ALREADY_EXISTS THREAD_FULL TOO_LARGE/;

use constant ALL_OK				=> 0;
use constant TRY_AGAIN			=> 1;
use constant FORGET_IT			=> 2;
use constant NONEXIST			=> 3;
use constant ALREADY_EXISTS		=> 4;
use constant THREAD_FULL		=> 5;
use constant TOO_LARGE			=> 6;
