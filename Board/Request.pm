package Board::Request;

use strict;
use warnings;

require Exporter;
our @ISA=qw/Exporter/;
our @EXPORT=qw/THREAD RANGE PAGE POSTNO MEDIA/;

sub THREAD($;$){
	my $num=$_[0];
	my $lastmod=$_[1];
	my @treq = ($num, $lastmod);
	bless \@treq,"Board::Request::THREAD";
}
sub RANGE($$){
	my $num=$_[0];
	my $limit=$_[1];
	my @range = ($num, $limit);
	bless \@range,"Board::Request::RANGE";
}
sub PAGE($;$){
	my $num=$_[0];
    my $lastmod=$_[1];
    my @preq = ($num, $lastmod);
	bless \@preq,"Board::Request::PAGE";
}

sub POSTNO($){
	my $num=$_[0];
	bless \$num,"Board::Request::POST";
}
sub MEDIA($){
    my $media=$_[0];
    bless \$media,"Board::Request::MEDIA";
}
