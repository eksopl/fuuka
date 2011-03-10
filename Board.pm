package Board;

use strict;
use warnings;
use Carp qw/confess cluck/;

require Exporter;
our @ISA=qw/Exporter/;

use Board::Request;
use Board::Errors;

sub not_supported(){
	confess "Not supported!";
}

sub new($;%){
	my $class=shift;
	my(%info)=@_;
	
	confess "This is an abstract class, dumbass!"
		if $class eq "Board";
	
	return bless{
		%info,
		
		opts		=> [{%info}],
		classname	=> $class,
	},$class;
}

sub clone{
	my($self,%info)=@_;
	
	my($newinfo,@args)=@{ $self->{opts} };
	
	$newinfo->{$_}=$info{$_} foreach keys %info;
	
	$self->{classname}->new(@args,%$newinfo);
}

sub new_post($@){
	my $self=shift;
	bless {@_},"Board::Post";
}
sub new_thread($@){
	my $self=shift;
	bless {@_},"Board::Thread";
}
sub new_page($$){
	my $self=shift;
	bless {num=>$_[0],threads=>[]},"Board::Page";
}

sub flattern($$){
	my $self=shift;
	my($ref)=@_;
	
	return map{@{$_->{posts}}} @{$ref->{threads}}
		if ref $ref eq "Board::Page";
		
	return @{$ref->{posts}}
		if ref $ref eq "Board::Thread";
}

sub get_media_preview($$){not_supported}
sub get_media($$){not_supported}
sub get_post($$){not_supported}
sub get_thread($$){not_supported}
sub get_page($$){not_supported}

sub post($;%){not_supported}
sub insert($$$){not_supported}
sub insert_media($$@){not_supported}
sub insert_media_preview($$@){not_supported}
sub delete($$;$){not_supported}
sub clean($){not_supported}

sub warn{
	my($self,$cat,$text)=@_;
	$text||=$self->errstr;
	$cat||='general';
	
#	print "$cat: $text\n";
}

sub ok{
	my($self)=@_;
	
	$self->error(0)
}

sub error{
	my($self,$code,$str)=@_;
	
	return $self->{errcode} unless defined $code;
	
	$self->{errcode}=$code;
	$self->{errstr}=$code?$str:"";
}

sub errstr{
	my($self)=@_;
	
	$self->{errstr}
}

sub content($$){
	my $self=shift;
	my($ref)=@_;
	
	confess "arg '$ref' is not a valid reference"
		unless ref $ref and (ref $ref)=~/^Board::Request::(THREAD|PAGE|POST)$/;

	my $sub;
	for($1){
		/THREAD/	and $sub=sub{$self->get_thread($$ref)},last;
		/PAGE/		and $sub=sub{$self->get_page($$ref)},last;
		/POST/		and $sub=sub{$self->get_post($$ref)},last;
	}
	
REDO:
	my $contents=$sub->();
	$self->warn($self->error) and goto REDO
		if $self->error and $self->error==TRY_AGAIN;
	
#	print "c ".(ref $ref)." ".$$ref."\n";
	
	$contents
}

sub threads($$){
	my $self=shift;
	my($page)=@_;
	
	my $p=$self->content(PAGE $page);
	map{$_->{num}}@{$p->{threads}};
}

sub bump($$$%){
	my $self=shift;
	my($num,$text,%args)=@_;
	
	my($err,$last)=$self->post(
		parent		=> $num,
		comment		=> $text,
		%args,
	);
	
	return $err if $err;
	return "Unknown error when ghost bumping" unless $last;
	
	($self->delete($last),$last);
}

sub text($$){
	my $self=shift;
	my($ref)=@_;
	
	my $content=$self->content($ref);
	
	grep{$_} $self->clean_text(
		map{$_->{comment}} $self->flattern($content)
	);
}

sub do_clean($$){
	my($self)=shift;

	for(shift){	
		s/&\#(\d+);/chr $1/gxse;
		s!&gt;!>!g;
		s!&lt;!<!g;
		s!&quot;!"!g;
		s!&amp;!&!g;
		
		s!\s*$!!gs;
		s!^\s*!!gs;
	
		return $_;
	}
}

sub clean_text($@){
	my($self)=shift;
	my @v;
	for(@_){
		push @v,$self->do_clean($_) if $_;
	}
	@v;
}

sub tripcode{
	my($self,$name)=@_;
	
	if($name=~/^(.*?)(#)(.*)$/){
		my($namepart,$marker,$trippart)=($1,$2,$3);
		my($trip,$sectrip)=$trippart=~/^(.*?)(?:#+(.*))?$/;
		
		if($sectrip){
			eval{
				use Digest::SHA1 'sha1_base64';
				use MIME::Base64;
			
				$sectrip='!!'.substr(sha1_base64($sectrip.decode_base64($self->{secret})), 0, 11);	
			};
			
			$sectrip='' if $@;
		}
		
		if($trip){
			# Actually, I am already relying on 5.10 features (lexical $_),
			# so there's nothing wrong in assuming that I have Encode,
			# but oh well
			eval{ 
				# 2ch trips are processed as Shift_JIS whenever possible
				use Encode qw/decode encode/;
				
				$trip=encode("Shift_JIS",$trip);
			};
			
			my $salt=substr $trip."H..",1,2;
			$salt=~s/[^\.-z]/./g;
			$salt=~tr/:;<=>?@[\\]^_`/ABCDEFGabcdef/; 
			$trip="!".substr crypt($trip,$salt),-10;
		}
		
		return $namepart,$trip.$sectrip;
	}

	$name,""
}

sub troubles($@){
	my $self=shift;
	
	open HANDLE,">>panic.txt";
	print HANDLE @_;
	close HANDLE;
	
	cluck @_;
}

1;
