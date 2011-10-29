package Board::Request;

use strict;
use warnings;

require Exporter;
our @ISA=qw/Exporter/;
our @EXPORT=qw/THREAD RANGE PAGE POSTNO/;

sub THREAD($){
	my $num=$_[0];
	bless \$num,"Board::Request::THREAD";
}
sub RANGE($$){
    my $num=$_[0];
    my $limit=$_[1];
    bless \$num,"Board::Request::RANGE";
    bless \$limit,"Board::Request::RANGE";
    return(\$num, \$limit);
}
sub PAGE($){
	my $num=$_[0];
	bless \$num,"Board::Request::PAGE";
}

sub POSTNO($){
	my $num=$_[0];
	bless \$num,"Board::Request::POST";
}

