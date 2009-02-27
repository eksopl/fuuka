package Board::Request;

use strict;
use warnings;

require Exporter;
our @ISA=qw/Exporter/;
our @EXPORT=qw/THREAD PAGE POSTNO/;

sub THREAD($){
	my $num=$_[0];
	bless \$num,"Board::Request::THREAD";
}
sub PAGE($){
	my $num=$_[0];
	bless \$num,"Board::Request::PAGE";
}

sub POSTNO($){
	my $num=$_[0];
	bless \$num,"Board::Request::POST";
}

