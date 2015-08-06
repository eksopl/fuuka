package Board::Yotsuba;

use strict;
use warnings;

use Board::WWW;
use Board::Errors;
our @ISA = qw/Board::WWW/;


sub get_board_list($) {
    my $board = shift;

    return {
    	link => "http://boards.4chan.org/$board",
    	img_link => "http://i.4cdn.org/$board",
    	preview_link => "http://0.t.4cdn.org/$board",
    	html => "http://boards.4chan.org/$board/",
    	script => "http://sys.4chan.org/$board/imgboard.php"
	};
}

sub new{
	my $class=shift;
	my($board)=shift;
	my $self=$class->SUPER::new(@_);
	
	$self->{name}=$board;
	$self->{renzoku}=20*1000000;
	my $board_list = get_board_list($board);
	$self->{$_} = $board_list->{$_}
		foreach keys %$board_list;
	
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
		$text=~m!(\d+)/(\d+)/(\d+) \(\w+\) (\d+):(\d+)(?::(\d+))?!x;
	
	use Time::Local;
	timegm(($sec or (time%60)),$min,$hour,$mday,$mon-1,$year);
}


sub new_yotsuba_post($$$$$$$$$$$$){
	my $self=shift;
	my($link,$orig_filename,$spoiler,$filesize,$width,$height,$filename,$twidth,$theight,
		$md5,$num,$title,$email,$name,$trip,$capcode,$date,$sticky,$comment,
		$omitted,$parent) = @_;
		
	my($type, $media, $preview, $timestamp);
	
	# Extract extra info we need from media links
	if($link){
		(my $number, $type)=$link=~m!/(\d+)\.(\w+)!;
		$orig_filename //= "$number.$type";
		$media = ($filename or "$number.$type");
		$preview = "${number}s.jpg";
	} else {
		($type, $media, $preview) = ("", "", "");
	}
	
	# Thumbnail dimensions are meaningless if the image is spoilered
	if($spoiler) {
		$twidth = 0;
		$theight = 0;
	}
	
	$timestamp = $self->parse_date($date);
		
	$self->new_post(
		link		=>($link or ""),
		type		=>($type or ""),
		media		=> $media,
		media_hash	=> $md5,
		media_filename	=> $orig_filename,
		media_size	=> ($filesize and $self->parse_filesize($filesize) or 0),
		media_w		=> ($width or 0),
		media_h		=> ($height or 0),
		preview		=> $preview,
		preview_w	=> ($twidth or 0),
		preview_h	=> ($theight or 0),
		num			=> $num,
		parent		=> $parent,
		title		=> ($title and $self->_clean_simple($title) or ""),
		email		=> ($email or ""),
		name		=> $self->_clean_simple($name),
		trip		=> ($trip or ""),
		date		=> $timestamp,
		comment		=> $self->do_clean($comment),
		spoiler		=> ($spoiler ? 1 : 0),
		deleted		=> 0,
		sticky		=> ($sticky ? 1 : 0),
		capcode		=> ($capcode or 'N'),
		omitted		=> ($omitted ? 1 : 0)
	);
}

sub parse_thread($$){
	my $self=shift;
	my($text)=@_;
	my $post = $self->parse_post($text,0);

	$self->troubles("Error parsing thread (see failed post above)\n------\n") and return
		unless defined $post->{num};
		
	my $omposts = $1 if
		$text=~m!<span \s class="info">\s*<strong>([0-9]*) \s posts \s omitted!xs;
		
	my $omimages = $1 if
		$text=~m!<em>\(([0-9]*) \s have \s images\)</em>!xs;
				
	$self->new_thread(
		num			=> $post->{num},
		omposts		=> ($omposts or 0),
		omimages	=> ($omimages or 0),
		posts		=> [$post],
		allposts	=> [$post->{num}]
	)
}

sub parse_post($$$){
	my $self = shift;
	my($post,$parent) = @_;
	my ($num, $title, $email, $name, $trip, $capcode, $capalt, $uid, $date, $link, 
		$spoiler, $filesize, $width, $height, $media, $md5, $twidth, $theight, $comment,
		$omitted, $sticky, $filename, $capold, $spoilerfn);

	$num = $1 if
		$post=~m!<div \s id="p([^"]*)" \s class="post \s [^"]*">!xs;

	$title = $1 if
		$post=~m!<span \s class="subject">([^<]*)</span>!xs;

    $email = $1 if
        $post=~m!<a \s href="mailto:([^"]*)" \s class="useremail">!xs;

	($name, $trip, $capcode, $capalt, $uid) = ($1, $2, $3, $4, $5) if
		$post=~m!<span \s class="name [^"]*">(?:<span [^>]*>)?([^<]*)(?:</span>)?</span> \s*
				(?:<span \s class="postertrip">(?:<span [^>]*>)?([^<]*)(?:</span>)?</span>)? \s*
				(?:<strong \s class="capcode [^>]*>\#\# \s (.)[^<]*</strong>)? \s*
				(?:</a>)? \s*
				(?:<span \s class="posteruid">\(ID: \s (?: <span [^>]*>(.)[^)]* 
					| ([^)]*))\)</span>)?
				!xs;
	
	$capold = $1 if
	    $post=~m!<span \s class="commentpostername"><span [^>]*>\#\# \s (.)[^<]*</span></span>!xs;
	
	$capcode //= $capalt // $capold;

	$date = $1 if
		$post=~m!<span \s class="dateTime" [^>]*>([^<]*)</span>!xs;

	($spoilerfn, $link, $spoiler, $filesize, $width, $height, $filename, $md5, $theight, $twidth) = 
		($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) if
		$post=~m!<div \s class="fileText" \s id="[^"]*"(?: \s* title="([^"]*)")?>File: \s <a \s href="([^"]*)"[^<]*</a>\s\((Spoiler \s Image,)? \s* ([\d\sGMKB\.]+),
				\s* (\d+)x(\d+) (?:, \s* <span>([^<]*)</span>)?.*? 
				<img \s src="[^"]*" .*? data-md5="([^"]*)" \s style="height: \s 
				([0-9]*)px; \s width: \s ([0-9]*)px;"!xs;

        $filename //= $spoilerfn;

	$comment = $1 if
		$post=~m!<blockquote \s class="postMessage" [^>]*>(.*?)</blockquote>!xs;
		
	$sticky = 1 if
		$post=~m!<img \s src="[^"]*" \s alt="Sticky" \s title="Sticky"[^>]*>!xs;
		
	$omitted = 1 if
		$post=~m!<span \s class="abbr">Comment \s too \s long!xs;

	$self->troubles("Error parsing post $num:\n------\n$post\n------\n") and return
		unless ($num and defined $name and $date and defined $comment);

	$self->new_yotsuba_post(
		$link,undef,$spoiler,$filesize,$width,$height,$filename,$twidth,$theight,
		$md5,$num,$title,$email,$name,$trip,$capcode,$date,$sticky,$comment,$omitted,
		$parent
	)
}

sub link_page($$){
	my $self=shift;
	my($page)=@_;

	$page||="";

	"$self->{link}/$page";
}

sub link_thread($$){
	my $self=shift;
	my($thread)=@_;

	$thread?
		"$self->{link}/res/$thread":
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
	
	$post->{preview} or $self->error(FORGET_IT,"This post doesn't have any media preview"),return;
	
	my $data=$self->wget_ref("$self->{preview_link}/thumb/$post->{preview}?" . time);
	
	$data;
}


sub get_media($$){
	my $self=shift;
	my($post)=@_;
	
	$post->{media_filename} or $self->error(FORGET_IT,"This post doesn't have any media"),return;
	
	my $data=$self->wget_ref("$self->{img_link}/src/$post->{media_filename}?" . time);
	
	$data;
}

sub get_post($$){
	my $self=shift;
	my($postno)=@_;
	
	my($res,undef)=$self->wget($self->link_post($postno));
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

sub get_thread($$;$){
	my $self=shift;
	my($thread,$lastmod)=@_;

	my ($res,$httpres)=$self->wget($self->link_thread($thread),undef,$lastmod);
	return if $self->error;
	
	my $t=undef;
	while($res=~m!
		(<div \s class="postContainer \s (opContainer|replyContainer)" [^>]*>.*?</blockquote>
		\s* </div> 
		(?: \s* <div [^>]*> \s* <span \s class="info">.*?</span>)?)
	!gxs) {
		my($text,$type)=($1,$2);
		if($type eq 'opContainer') {
			$self->troubles("Two thread posts in one thread at " . $self->link_thread($thread) . "(thread $thread). Already had $t->{num}, trying to parse:\n$text\n\n------\n\n") if $t;
			$t=$self->parse_thread($text);
		} else {
			$self->troubles("posts without thread:\n$res\n\n------\n\n") unless $t;
			my $pt = $self->parse_post($text,$t->{num});
			next unless $pt;
			push @{$t->{posts}},$pt;
			push @{$t->{allposts}},$pt->{num};
	   }
	}

	$t->{lastmod} = $httpres->header("Last-Modified");
	
	$self->ok;
	$t
}

sub get_page($$){
	my $self=shift;
	my($page,$lastmod)=@_;
	
	my($res,$httpres)=$self->wget($self->link_page($page),undef,$lastmod);
	return if $self->error;
	
	my $t=undef;
	my $p=$self->new_page($page);
	while($res=~m!
		(<div \s class="postContainer \s (opContainer|replyContainer)" [^>]*>.*?</blockquote>
		\s* </div> 
		(?: \s* <div [^>]*> \s* <span \s class="info">.*?</span>)?)
	!gxs) {
		my($text,$type)=($1,$2);
		if($type eq 'opContainer') {
			$t=$self->parse_thread($text);
			push @{$p->{threads}},$t if $t;
	   } else {
			my $pt = $self->parse_post($text,$t->{num});
			next unless $pt;
			push @{$t->{posts}},$pt;
			push @{$t->{allposts}},$pt->{num};
		}
	}

	$p->{lastmod} = $httpres->header("Last-Modified");
	
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

	# SOPA spoilers
	#s!<span class="spoiler"[^>]*>(.*?)</spoiler>(</span>)?!$1!g;

	# Escaping tags we don't want users to use
	s!\[(banned|moot)\]![${1}:lit]!g;

	# code tags
	s!<pre [^>]*>![code]!g;
	s!</pre>![/code]!g;

	# Comment too long. Also, exif tag toggle
	s!<span class="abbr">.*?</span>!!g;
	
	# (USER WAS BANNED|WARNED FOR THIS POST)
	s!<(?:b|strong) style="color:\s*red;">(.*?)</(?:b|strong)>![banned]${1}[/banned]!g;

	# moot text
	s!<div style="padding: 5px;margin-left: \.5em;border-color: #faa;border: 2px dashed rgba\(255,0,0,\.1\);border-radius: 2px">(.*?)</div>![moot]${1}[/moot]!g;

	# Bold text
	s!<(?:b|strong)>(.*?)</(?:b|strong)>![b]${1}[/b]!g;

	# Who are you quoting? (we reparse quotes on our side)
	s!<font class="unkfunc">(.*?)</font>!$1!g;
	s!<span class="quote">(.*?)</span>!$1!g;
	s!<span class="(?:[^"]*)?deadlink">(.*?)</span>!$1!g;

	# Get rid of links (we recreate them on our side)
	s!<a[^>]*>(.*?)</a>!$1!g;
	
	# Spoilers
	s!<span class="spoiler"[^>]*>![spoiler]!g;
	s!</span>![/spoiler]!g;

	s!<s>![spoiler]!g;
	s!</s>![/spoiler]!g;

	# <wbr>
	s!<wbr>!!g;

	# Newlines
	s!<br \s* /?>!\n!gx;

	$self->_clean_simple($_);
}


1;
