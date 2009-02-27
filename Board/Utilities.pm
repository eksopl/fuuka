package Board::Utilities;

use strict;

use Exporter qw/import/;
our @EXPORT=qw/size_string file_copy status cat now vsleep usage $board $num $home %FLAGS $USAGE_ARGS $USAGE_TEXT DOCS/;
our($board,$num,$home,%FLAGS,$USAGE_ARGS,$USAGE_TEXT),;

use Time::HiRes qw/usleep gettimeofday/;
$|++;

use constant DOCS				=> 'b:/doc';

-d DOCS or die "Directory ".DOCS." doesn't exist";

our($home);
BEGIN{($home)=$0=~/(.*)[\/\\].*/;$home||=".";}
use lib $home;

sub usage(){
	print <<HERE;
Usage: $0 $USAGE_ARGS
$USAGE_TEXT
HERE
	exit;
}

sub size_string($){
	my($val)=@_;
	
	return sprintf "%d B",$val if $val<1024;
	return sprintf "%d KB",$val if ($val/=1024)<1024;
	return sprintf "%.2f MB",$val if ($val/=1024)<1024;
	return sprintf "%.2f GB",$val if ($val/=1024)<1024;

	"very large"
}

sub cat($){
	local $/;
	
	map{
		open HANDLE,"<",$_ or die "$! - $_";
		binmode HANDLE;
		
		my $data=<HANDLE>;
		
		close HANDLE;
		
		$data
	} @_;
}
sub file_copy($$;$){
	my($if,$of,$noise)=@_;
	my $buf;
	
	CORE::open O,">",$of or die "$! - $of";
	
	binmode O;
	
	print O cat $if;
	print O $noise if $noise;
	
	close O;
}

BEGIN{
	my($snow,$sus)=gettimeofday;
	sub now(){
		my($now,$us)=gettimeofday;
		return 1000000*($now-$snow)+($us-$sus);
	}
}
BEGIN{
	my $length=0;
	sub status(@){
		print "\b"x$length," "x$length,"\b"x$length;
		
		my(@lines)=split /\r?\n/,join "",@_;
		print join "\n",@lines;
		$length=length pop @lines;
	}
}
sub vsleep($;$){
	my($duration,$period)=(@_,100000);
	my $end=now+$duration;
	
	while($end>now){
		status sprintf "sleeping %.1fs",($end- now)/1000000;
		
		usleep $period;
	}
	
	status;
}

my(@ARGS);
while($_=shift @ARGV){
	/^--(\w+)$/ and do{
		$FLAGS{$1}=shift @ARGV;
	},next;
	
	/^--(\w+)=(.*)$/ and do{
		$FLAGS{$1}=$2;
	},next;
	
	/^-(\w+)$/ and do{
		$FLAGS{$_}=1
			foreach split //,$1;
	},next;
	
	push @ARGS,$_;
}

@ARGV=@ARGS;

my $board_line=shift @ARGV
	or die "You didn't specify board name\n";

our($name,$num)=($board_line or "")=~m!^>*(?:/?([a-z]+))?(?:/?(\d+))?$!i
	or die "Wrong format: $board_line\n";

my(@OPTS)=(($name or 'jp'),timeout=>24);

push @OPTS,proxy=>$FLAGS{proxy} if $FLAGS{proxy};

use Board::Yotsuba;
our $board=Board::Yotsuba->new(@OPTS)
	or die "No such board: $name\n";

1;
