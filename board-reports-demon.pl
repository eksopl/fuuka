#!perl

use strict;
use warnings;
use utf8;

sub info(@);

BEGIN{require "board-config.pl"}
use Board::Mysql;

binmode *STDOUT,":utf8";

use Time::HiRes qw/gettimeofday usleep/;

sub process();
sub usage();
sub reload_reports();

my $settings=BOARD_SETTINGS;
my $board_names=[keys %$settings];
my @boards=map{SPAWNER->($_)} @$board_names;
my $loc=REPORTS_LOCATION;
my $imgloc=IMAGES_LOCATION;
my $term=GNUPLOT_TERMINAL;
my @reports;
my @report_files;
my %mtimes;

mkdir "$imgloc";
mkdir "$imgloc/graphs";
mkdir "$imgloc/graphs/$_" foreach @$board_names;
mkdir "$loc";
mkdir "$loc/status";
mkdir "$loc/status/$_" foreach @$board_names;

sub uncrlf($){
	$_[0]=~s/\r?\n?\r?$//;
	
	$_[0]
}

sub mtime($){
	my($filename)=@_;
	
	my(@stat)=stat $filename or return 0;
	
	$stat[9]
}

sub reload_reports(){
	@reports=();
	@report_files=();
	push @report_files,$loc;
	$mtimes{$loc}=mtime $loc;
	
	opendir DIRHANDLE,$loc or die "$! - $loc";
MAINLOOP:
	while($_=readdir DIRHANDLE){
		next if $_ =~ /^\./;
		my $filename="$loc/$_";
		
		next unless -f $filename;
		my %opts;
		
		push @report_files,$filename;
		$mtimes{$filename}=mtime $filename;
		
		open HANDLE,$filename or die "$! - $filename";
		for(<HANDLE>){
			uncrlf($_);
			
			/([\w\d\-]*)\s*:\s*(.*)/ or warn "$filename: wrong report file format: $_" and next;
			
			$opts{lc $1}=$2;
		}
		close HANDLE;
		
		warn "$filename: wrong format: must have field $_" and next MAINLOOP
			foreach grep{not $opts{$_}} "query","mode","refresh-rate";
		
		$opts{filename}="$_";
		
		if($opts{mode} eq 'graph'){
			$opts{'result-location'}="$imgloc/graphs";
			$opts{'result'}="$_.png";
		} else{
			$opts{'result-location'}="$loc/status";
			$opts{'result'}=$_;
		}
		
		push @reports,\%opts;
	}
	
	closedir DIRHANDLE;
}

reload_reports;

my $lastmtime=0;
while(1){
	for(@report_files){
		reload_reports if mtime $_>$mtimes{$_};
	}
	
	for my $board(@boards){
	for(@reports){
		my $remake_time=$_->{"refresh-rate"}-(time- mtime "$_->{'result-location'}/$board->{name}/$_->{result}");
		do_report($_,$board) if $remake_time<0;
	}
	}
	
	sleep 1;
}

sub benchmark($){
	my $sub=shift;
	my($s,$us)=gettimeofday;
	$sub->();
	my($s_new,$us_new)=gettimeofday;
	($s_new-$s)+($us_new-$us)/1_000_000;
}

sub do_report{
	my($ref,$board)=@_;
	my $name=$ref->{filename};
	
	my $list;
	info sprintf "$name, $board->{name}: %.3f seconds taken",benchmark sub{
		my $query=$ref->{query};
		$query=~s/%%BOARD%%/$board->{name}/g;
		$query=~s/%%NOW%%/yotsutime/ge;
		$list=$board->query($query);
	};
	
	die $board->errstr if $board->error;
	
	if($ref->{mode} eq 'graph' and GNUPLOT){
		my $xstart = $list->[0][0];
		my $xend   = $list->[-1][0];
		open HANDLE,">$loc/graphs/$name.data" or die "$! - $loc/graphs/$name.data";
		print HANDLE (join "\t",@$_),"\n" foreach @$list;
		close HANDLE;
		
		open INFILE,"$loc/graphs/$name.graph" or die "$! - $loc/graphs/$name.graph";
		open OUTFILE,">$loc/graphs/$name.graph+" or die "$! - $loc/graphs/$name.graph+";
		
		while(defined(local $_=<INFILE>)){
			s!%%INFILE%%!$loc/graphs/$name.data!g;
			s!%%OUTFILE%%!$ref->{'result-location'}/$board->{name}/$ref->{result}!g;
			s!%%XSTART%%!$xstart!g;
			s!%%XEND%%!$xend!g;
			s!%%TERM%%!$term!g;
			print OUTFILE $_;
		}
		
		close OUTFILE;
		close INFILE;
		
		system(GNUPLOT,"$loc/graphs/$name.graph+");
		
#		unlink "$loc/graphs/$name.graph+","$loc/graphs/$name.data";
	} else{
		open HANDLE,">$ref->{'result-location'}/$board->{name}/$ref->{result}" or die "$! - $ref->{'result-location'}/$board->{name}/$ref->{result}";
		binmode HANDLE,":utf8";
		print HANDLE time,"\n";
		for(@$list){
			print HANDLE (join "|",map{s !\|!\\v!g;$_}@$_),"\n";
		}
		close HANDLE;
	}
}


sub info(@){
	print "".localtime()." ",@_,"\n";
} 




