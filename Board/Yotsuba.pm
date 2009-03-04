package Board::Yotsuba;

use strict;
use warnings;

use Board::WWW;
use Board::Errors;
our @ISA = qw/Board::WWW/;

my %boards_list;

sub new{
	my $class=shift;
	my($board)=shift;
	my $self=$class->SUPER::new(@_);
	
	return unless $boards_list{$board};
	
	$self->{name}=$board;
	$self->{renzoku}=20*1000000;
	$self->{$_}=$boards_list{$board}->{$_}
		foreach keys %{$boards_list{$board}};
	
	$self->{opts}=[{@_},$board];
	

	bless $self,$class;
}

my %size_multipliers=(
	B	=> 1,
	KB	=> 1024,
	MB	=> 1024*1024,
);

sub parse_filesize($$){
	my $self=shift;
	my($text)=@_;
	
	my($v,$m)=$text=~/([\.\d]+) \s (.*)/x;
	
	$size_multipliers{$m} or $self->troubles("error parsing filesize: '$text'") and return 0;
	$v*$size_multipliers{$m};
}

sub parse_date($$){
	my $self=shift;
	my($text)=@_;
	
	my($mon,$mday,$year,$hour,$min,$sec)=
		$text=~m!(\d+)/(\d+)/(\d+) \(\w+\) (\d+):(\d+)(?:(\d+))?!x;
	
	use Time::Local;
	timegm($sec or (time%60),$min,$hour,$mday,$mon-1,$year);
}


sub new_yotsuba_post($$$$$$$$$$$$){
	my $self=shift;
	my($link,$media_filename,$spoiler,$filesize,$width,$height,$filename,$twidth,$theight,
		$md5base64,$num,$title,$email,$name,$trip,$capcode,$date,$comment,$omitted,$parent)=@_;
	
	my($type,$media,$preview,$timestamp,$md5);
	if($link){
		(my $number,$type)=$link=~m!/src/(\d+)\.(\w+)!;
		$media=($filename or "$number.$type");
		$preview="${number}s.jpg";
		$md5=$md5base64;
	} else{
		($type,$media,$preview,$md5)=("","","","");
	}
	$timestamp=$self->parse_date($date);
	$omitted=$omitted?1:0;

	$self->new_post(
		link		=>($link or ""),
		type		=>($type or ""),
		media		=> $media,
		media_hash	=> $md5,
		media_filename	=> $media_filename,
		media_size	=>($filesize and $self->parse_filesize($filesize) or 0),
		media_w		=>($width or 0),
		media_h		=>($height or 0),
		preview		=> $preview,
		preview_w	=>($twidth or 0),
		preview_h	=>($theight or 0),
		num			=> $num,
		parent		=> $parent,
		title		=>($title and $self->_clean_simple($title) or ""),
		email		=>($email or ""),
		name		=> $self->_clean_simple($name),
		trip		=>($trip or ""),
		date		=> $timestamp,
		comment		=> $self->do_clean($comment),
		spoiler		=>($spoiler?1:0),
		deleted		=> 0,
		capcode		=>($capcode or 'N'),
		omitted		=> $omitted,
	);
}

sub parse_thread($$){
	my $self=shift;
	my($text)=@_;
	$text=~m!	(?:
					<a \s href="([^"]*/src/(\d+\.\w+))"[^>]*>[^<]*</a> \s*
					\- \s* \((Spoiler \s Image, \s)?([\d\sGMKB\.]+)\, \s (\d+)x(\d+)(?:, \s* <span \s title="([^"]*)">[^<]*</span>)?\) \s*
					</span> \s* 
					(?:
						<br>\s*<a[^>]*><img \s+ src=\S* \s+ border=\S* \s+ align=\S* \s+ (?:width="?(\d+)"? \s height="?(\d+)"?)? [^>]*? md5="?([\w\d\=\+\/]+)"? [^>]*? ></a> \s*
						|
						<a[^>]*><span \s class="tn_thread"[^>]*>Thumbnail \s unavailable</span></a>
					)
					|
					<img [^>]* alt="File \s deleted\." [^>]* > \s*
				)
				<a[^>]*></a> \s*
				<input \s type=checkbox \s name="(\d+)"[^>]*><span \s class="filetitle">(?>(.*?)</span>) \s*
				<span \s class="postername">(?:<span [^>]*>)?(?:<a \s href="mailto:([^"]*)"[^>]*>)?([^<]*?)(?:</a>)?(?:</span>)?</span>
				(?: \s* <span \s class="postertrip">(?:<span [^>]*>)?([a-zA-Z0-9\.\+/\!]+)(?:</a>)?(?:</span>)?</span>)?
				(?: \s* <span \s class="commentpostername"><span [^>]*>\#\# \s (.?)[^<]*</span></span>)?
				\s ([^>]*) \s \s* <span[^>]*> \s* 
				(?>.*?</span>) \s*
				<blockquote>(?>(.*?)(<span \s class="abbr">(?:.*?))?</blockquote>)
				(?:<span \s class="oldpost">[^<]*</span><br> \s*)?
				(?:<span \s class="omittedposts">(\d+).*?(\d+)?.*?</span>)?
	!xs or $self->troubles("error parsing thread\n------\n$text\n------\n") and return;
	$self->new_thread(
		num			=> $11,
		omposts		=>($20 or 0),
		omimages	=>($21 or 0),
		posts		=>[$self->new_yotsuba_post(
			$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,0
		)],
	)
}

sub parse_post($$$){
	my $self=shift;
	my($text,$parent)=@_;
	$text=~m!	<td \s id="(\d+)"[^>]*> \s*
				<input[^>]*><span \s class="replytitle">(?>(.*?)</span>) \s*
				<span \s class="commentpostername">(?:<span [^>]*>)?(?:<a \s href="mailto:([^"]*)"[^>]*>)?([^<]*?)(?:</a>)?(?:</span>)?</span>
				(?: \s* <span \s class="postertrip">(?:<span [^>]*>)?([a-zA-Z0-9\.\+/\!]+)(?:</a>)?(?:</span>)?</span>)?
				(?: \s* <span \s class="commentpostername"><span [^>]*>\#\# \s (.?)[^<]*</span></span>)?
				\s ([^>]*) \s \s* <span[^>]*> \s* 
				(?>.*?</span>) \s*
				(?:
					<br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; \s*
					<span \s class="filesize">File \s :
					<a \s href="([^"]*/src/(\d+\.\w+))"[^>]*>[^<]*</a> \s*
					\- \s* \((Spoiler \s Image,)?([\d\sGMKB\.]+)\, \s (\d+)x(\d+)(?:, \s* <span \s title="([^"]*)">[^<]*</span>)?\)
					</span> \s*
					(?:
						<br>\s*<a[^>]*><img \s+ src=\S* \s+ border=\S* \s+ align=\S* \s+ (?:width=(\d+) \s height=(\d+))? [^>]*? md5="?([\w\d\=\+\/]+)"? [^>]*? ></a> \s*
						|
						<a[^>]*><span \s class="tn_reply"[^>]*>Thumbnail \s unavailable</span></a>
					)
					|
					<br> \s*
					<img [^>]* alt="File \s deleted\." [^>]* > \s*
				)?
				<blockquote>(?>(.*?)(<span \s class="abbr">(?:.*?))?</blockquote>)
				</td></tr></table>
	!xs or $self->troubles("error parsing post\n------\n$text\n------\n") and return;
	
	$self->new_yotsuba_post(
		$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$1,$2,$3,$4,$5,$6,$7,$18,$19,$parent
	)
}

sub link_page($$){
	my $self=shift;
	my($page)=@_;

	$page||="imgboard";

	"$self->{link}/$page.html";
}

sub link_thread($$){
	my $self=shift;
	my($thread)=@_;

	$thread?
		"$self->{link}/res/$thread.html":
		$self->link_page(0);
}

sub link_post($$){
	my $self=shift;
	my($postno)=@_;

	"$self->{link}/imgboard.php?res=$postno"
}

sub magnitude($$){
	my $self=shift;
	local($_)=@_;
	
	/Flood detected/ and return (TRY_AGAIN,"flood");

	/Thread specified does not exist./ and return (NONEXIST,"thread doesn't exist");
	
	/Duplicate file entry detected./ and return (ALREADY_EXISTS,"duplicate file");
	/File too large/ and return (TOO_LARGE,"file too large");
	
	/^\d+ / and return (FORGET_IT,$_);
	
	/Max limit of \d+ image replies has been reached./ and return (THREAD_FULL,"image limit");
	
	/No text entered/ and return (FORGET_IT,"no text entered");
	
	/Can't find the post / and return (NONEXIST,"post doesn't exist");
	
	/No file selected./ and return (FORGET_IT,"no file selected");
	die $_;
}


sub get_media_preview($$){
	my $self=shift;
	my($post)=@_;
	
	$post->{link} or $self->error(FORGET_IT,"This post doesn't have any media preview"),return;
	
	my $data=$self->wget("$self->{link}/thumb/$post->{preview}");
	
	\$data;
}


sub get_media($$){
	my $self=shift;
	my($post)=@_;
	
	$post->{link} or $self->error(FORGET_IT,"This post doesn't have any media"),return;
	
	my $data=$self->wget($post->{link});
	
	\$data;
}

sub get_post($$){
	my $self=shift;
	my($postno)=@_;
	
	my $res=$self->wget($self->link_post($postno));
	return if $self->error;
	
	my($thread)=$res=~m!"0;URL=http://.*/res/(\d+)\.html#$postno"!
		or $self->error(FORGET_IT,"Couldn't find post $postno"),return;
	
	my $contents=$self->get_thread($thread);
	return if $self->error;
	
	my($post)=grep{$_->{num}==$postno} @{$contents->{posts}}
		or $self->error(FORGET_IT,"Couldn't find post $postno"),return;


	$self->error(0);
	$post
}

sub get_thread($$){
	my $self=shift;
	my($thread)=@_;

	my $res=$self->wget($self->link_thread($thread));
	return if $self->error;
	
	my $t;
	while($res=~m!(
			(?:
				(
					<span \s class="filesize">
					|
					<img \s src="[^"]*" \s alt="File \s deleted\.">
				)
				(?>.*?</blockquote>)
				(?:<span \s class="oldpost">[^<]*</span><br> \s*)?
				(?:<span \s class="omittedposts">[^<]*</span>)?
			)
			|
			(?:<table><tr><td \s nowrap \s class="doubledash">(?>.*?</blockquote></td></tr></table>))
	)!gxs){
		my($text,$type)=($1,$2);
		if($type){
			$self->troubles("two thread posts in one thread------$res------") if $t;
			$t=$self->parse_thread($text);
		}else{
			$self->troubles("posts without thread------$res------") unless $t;
			
			push @{$t->{posts}},$self->parse_post($text,$t->{num});
		}
	}
	
	$self->ok;
	$t
}

sub get_page($$){
	my $self=shift;
	my($page)=@_;
	
	my $res=$self->wget($self->link_page($page));
	return if $self->error;
	
	my $t;
	my $p=$self->new_page($page);
	while($res=~m!(
			(?:<(span) \s class="filesize">(?>.*?</blockquote>)
				(?:<span \s class="oldpost">[^<]*</span><br> \s*)?
				(?:<span \s class="omittedposts">[^<]*</span>)?)
			|
			(?:<table><tr><td \s nowrap \s class="doubledash">(?>.*?</blockquote></td></tr></table>))
	)!gxs){
		my($text,$type)=($1,$2);
		if($type){
			push @{$p->{threads}},$t if $t;
			$t=$self->parse_thread($text);
		}else{
			push @{$t->{posts}},$self->parse_post($text,$t->{num});
		}
	}
	
	$self->error(0);
	$p
}

sub post($;%){
	my $self=shift;
	my(%info)=@_;
	my($thread)=($info{parent} or 0);
	
	local $_=$self->wpost(
		$self->{script},
		$self->link_thread($thread),
		
		MAX_FILE_SIZE	=> '2097152',
		resto			=> $thread,
		name			=>($info{name} or ''),
		email			=>($info{email} or $info{mail} or ''),
		sub				=>($info{title} or ''),
		com				=>($info{comment} or ''),
		upfile			=>($info{file} or []),
		pwd				=>($info{password} or rand 0xffffffff),
		mode			=> 'regist',
	);
	
	return if $self->error;
	my($last)=(/<META HTTP-EQUIV="refresh" content="1;.*?\#(\d+)">/,/<!-- thread:\d+,no:(\d+) -->/);
	$self->error(0),return $last if /pdating page/;
	$self->error($self->magnitude($1)),return if /<font color=red [^>]*><b>(?:Error:)?\s*(.*?)<br><br>/;
	die "Unknown error when posting:-------$_--------"
}

sub delete{
	my $self=shift;
	my($num,$pass)=@_;
	
	local $_=$self->wpost_x_www(
		$self->{script},
		$self->link_page(0),
		
		$num	 , 'delete',
		mode	=> 'usrdel',
		pwd		=>($pass or 'wwwwww'),
	);
	
	return if $self->error;
	$self->error(0),return 0 if /<META HTTP-EQUIV="refresh"\s+content="0;URL=.*">/;
	$self->error($self->magnitude($1)),return if /<font color=red [^>]*><b>(?:Error:)?(.*?)<br><br>/;
	die "Unknown error when deleting post:-------$_--------"
}

sub _clean_simple($$){
   my($self)=shift;
   my($val)=@_;
   return $self->SUPER::do_clean($val);
}

sub do_clean($$){
	(my($self),local($_))=@_;

	s!<span class="abbr">.*?</span>!!g;
	
	s!<b style="color:red;">(.*?)</b>![banned]${1}[/banned]!g;
	
	s!<font class="unkfunc">(.*?)</font>!$1!g;
	s!<a[^>]*>(.*?)</a>!$1!g;
	
	s!<span class="spoiler"[^>]*>![spoiler]!g;
	s!</span>![/spoiler]!g;

	s!<br \s* /?>!\n!gx;
	
	$self->_clean_simple($_);
}

while(<<HERE=~/(\S+)\s+(\S+)\s+(\S+)\s+(.*)/g){
jp		zip		bin		Japan/General
a		zip		bin		Anime & Manga
an		zip		bin		Animals & Nature
b		img		dat		Random
c		zip		bin		Anime/Cute
cgl		orz		tmp		Cosplay & EGL
ck		zip		bin		Food & Cooking
cm		zip		bin		Cute/Male
co		zip		bin		Comics & Cartoons
d		orz		tmp		Hentai/Alternative
e		orz		tmp		Ecchi
g		zip		bin		Technology
gif		cgi		nov		Animated GIF
h		cgi		nov		Hentai
hr		orz		tmp		High Resolution
k		zip		bin		Weapons
m		zip		bin		Mecha
mu		zip		bin		Music
n		orz		tmp		News
o		zip		bin		Auto
p		zip		bin		Photography
po		zip		bin		Papercraft & Origami
r		cgi		nov		Request
s		cgi		nov		Sexy Beautiful Women
t		cgi		nov		Torrents
tv		zip		bin		Television & Film
u		orz		tmp		Yuri
v		zip		bin		Video Games
w		zip		bin		Anime/Wallpapers
wg		orz		tmp		Wallpapers/General
y		orz		tmp		Yaoi
i		cgi		nov		Oekaki
ic		cgi		nov		Artwork/Critique
HERE

	$boards_list{$1}={
		desc=>"$4",
		link=>"http://$2.4chan.org/$1",
		html=>"http://$2.4chan.org/$1/imgboard.html",
		script=>"http://$3.4chan.org/$1/imgboard.php",
	};
}

1;