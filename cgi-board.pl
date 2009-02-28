#!perl

use strict;
use utf8;

use CGI qw/-utf8/;
use CGI::Carp qw(fatalsToBrowser);
use CGI::Cookie;

use lib "b:/scripts";

use Board::Request;
use Board::Mysql;
use Board::Yotsuba;

BEGIN{require "board-config.pl"}

our $boards				= BOARD_SETTINGS;
our @boards				= sort keys %$boards;
our %boards				= %$boards;
our($board_name,$path)	= $ENV{PATH_INFO}=~m!^/(\w+)(/.*)?!;
our $board_desc			= html_encode($boards{$board_name}->{name});
our $loc				= IMAGES_LOCATION;
our $server_loc			= IMAGES_LOCATION_HTTP;
our $limit				= 20;
our $self				= "$ENV{SCRIPT_NAME}/$board_name";
our $cgi				= new CGI;
our %cookies			= fetch CGI::Cookie;
our $id					= unpack "N",pack "C4",split /\./,$ENV{REMOTE_ADDR};
	
use constant LOCAL		=> $ENV{REMOTE_ADDR} eq '127.0.0.1';

our $yotsuba_link		= $boards{$board_name}->{link};

BEGIN{require "templates.pl"}
BEGIN{require "messages.pl"}

show_index() unless $board_name;
$boards->{$board_name} or error("Board $board_name does not exist");

our $ghost_mode			= 0;
$ghost_mode				= 'yes' if
	$path=~m!^/(thread|post|page)/S!		or
	$cgi->param("page")=~/^S/				or
	$cgi->param("thread")=~/^S/				or
	$cgi->param("post")=~/^S/				or
	$cgi->param("ghost")					;

$ghost_mode				= 'yes' if
	$cookies{'ghost'} and $cookies{'ghost'}->value eq 'yes' and
	$cgi->param("task")!='page';

our $board				= Board::Mysql->new($board_name,
	connstr			=> DB_CONNECTION_STRING,
	host			=> DB_HOST,
	database		=> DB_DATABSE_NAME,
	name			=> DB_USERNAME,
	password		=> DB_PASSWORD,
	images			=> IMAGES_LOCATION,
	secret			=> SECRET,
	renzoku			=> RENZOKU,
	renzoku3		=> RENZOKU3,
) or die "Couldn't use mysql board with table $board_name";

our @navigation=(
	[
		map{
		[$_,			$board_desc,							"$ENV{SCRIPT_NAME}/$_"]
		} @boards
	],[
		["index",		"Go to front page of archiver",			"$ENV{SCRIPT_NAME}"],
		["top",			"Go to first page of this board",		"$self"],
		["reports",		"",										"$self/reports"],
		["report a bug","Report a bug or suggest a feature",	"http://code.google.com/p/fuuka/issues/list"],
		
	]
);

our $navigation="<div>".(join "",map{
	"[ ".(join " / ",map{"<a href=\"$_->[2]\"".($_->[1] and " title=\"".html_encode($_->[1])."\"" or "").">$_->[0]</a>"}@$_)." ] "
}@navigation)."</div>";

sub cgi_params(){
	my %params;
	
	$cgi->param("$_") and $params{$_}=html_encode($cgi->param("$_"))
		foreach qw/search_text/;
	
	$cgi->param("$_") and $params{$_}=$cgi->param("$_")
		foreach qw/search_username search_tripcode search_del search_int search_ord task/;
	
	$params{ghost}='yes' if $ghost_mode;
	
	$params{delpass}=$cookies{'delpass'}->value if $cookies{'delpass'};
	
	%params
}

sub x_www_params(@){
	my(%args)=@_;
	
	html_encode(join "&",map{"$_=".link_encode($args{$_})}keys %args)
}

sub html_encode($){
	local $_=shift;
	s/&/&amp;/g;
	s/\</&lt;/g;
	s/\>/&gt;/g;
	s/"/&quot;/g;
	s/'/&#39;/g;
	s/,/&#44;/g;

	# repair unicode entities
	s/&amp;(\#[0-9]+;)/&$1/g;
	s/&amp;(\#x[0-9a-f]+;)/&$1/gi;
	
	$_;
}

sub link_encode($){
	local $_=shift;
	
	s/([^\-\w\d\.\&\=])/sprintf "%%%02x",ord $1/ge;
	s/ /+/g;
	
	$_
}

use constant BBCODE => {
	aa			=> ["<span class='aa'>",					"</span>"],
	spoiler		=> ["<span class='spoiler'>",				"</span>"],
	sup			=> ["<sup>",								"</sup>"],
	sub			=> ["<sub>",								"</sub>"],
	b			=> ["<b>",									"</b>"],
	i			=> ["<em>",									"</em>"],
	code		=> ["<code>",								"</code>"],
	m			=> ["<tt>",									"</tt>"],
	u			=> ["<span class='u'>",						"</span>"],
	o			=> ["<span class='o'>",						"</span>"],
	s			=> ["<span class='s'>",						"</span>"],
	EXPERT		=> ["<b><span class='u'><span class='o'>",	"</span></span></b>"],
	banned		=> ["<span class='banned'>",				"</span>"],
};

sub bbcode_encode($){
	my($line)=@_;
	my $res="";	
	my(@tags);
	my $quoting=0;
	
	while($line=~m!(.*?)(\[(/?)([\w]+)\])?!g){
		my($text,$fulltag,$closing,$tag)=($1,$2,$3,$4);
		$res.=$text;
		
		$tag or $res.=$fulltag,next;
		(my $html=BBCODE->{$tag}) or $res.=$fulltag,next;
		
		if($quoting and $tag eq 'code'){
			if(not $closing){
				push @tags,$tag;
				$quoting++;
			} else{
				pop @tags;
				$quoting--;
			}
			
			$res.=$fulltag if $quoting;
			$res.=$html->[1] unless $quoting;
		} elsif($quoting){
			$res.=$fulltag;
		} elsif(not $closing){
			push @tags,$tag;
			$res.=$html->[0];
			
			$quoting++ if $tag eq 'code';
		} elsif($tags[$#tags] eq $tag){
			pop @tags;
			$res.=$html->[1];
		} else{
			$res.=$fulltag;
		}
	}
	
	for(reverse @tags){
		$res.=BBCODE->{$_}->[1];
	}
	
	$res
}

sub format_comment($$){
	local $_=html_encode(shift);
	my($present_posts)=@_;
	
	s!(&gt;&gt;(\d+(?:&#44;)?\d+))(?: (.*))?!
		my($text,$num,$quote)=($1,$2,$3);
		$num=~s/&#44;/_/g;
		
		($present_posts->{$num}?
			qq{<a href="#p$num" onclick="replyhighlight('p$num')">$text</a>}:
			qq{<a href="}.(ref_post_far($num)).qq{">$text</a>}).
				($quote?qq{ <span class="unkfunc">$quote</span>}:"")
	!ge;
	
	# make URLs into links
#	s{(https?://[^\s<>"]*?)((?:\s|<|>|"|\.|\)|\]|!|\?|,|&#44;|&quot;)*(?:[\s<>"]|$))}{\<a href="$1"\>$1\</a\>$2}sgi;
	
	s!(\r?\n|^)(&gt;.*?)(?=$|\r?\n)!$1<span class="unkfunc">$2</span>$3!g;
	
	s/^\s*//;
	s/\s*$//;
	
	s!\r?\n!<br />!g;
	
	bbcode_encode($_)
}
sub simple_format($){
	local $_=html_encode(shift);
	
	s/^\s*//;
	s/\s*$//;
	
	s!\n!<br />!g;
	
	$_;
}
sub mtime($){
	my($filename)=@_;
	
	my(@stat)=stat $filename or return 0;
	
	$stat[9]
}

sub make_filesize_string($){
	my ($size)=@_;
	
	return sprintf("%d B", $size) unless int($size/1024);
	return sprintf("%d KB", $size/1024) unless int($size/1024/1024);
	return sprintf("%.2f MB", $size/1024/1024);
}

sub ref_post($$$){
	my($parent,$num,$subnum)=(@_,0,0);
	my($shadow)=$ghost_mode?"S":"";
	
	return "$self/thread/$shadow$num" unless $parent;
	return "$self/thread/$shadow$parent#p$num" unless $subnum;
	
	"$self/thread/$shadow$parent#p${num}_$subnum"
}
sub ref_post_far($;$){
	my($num,$subnum)=(@_);
	my($shadow)=$ghost_mode?"S":"";
	
	$num.="_$subnum" if $subnum;
	
	"$self/post/$shadow$num"
}
sub ref_post_text($$){
	my($num,$subnum)=(@_,0);
	my($shadow)=$ghost_mode?"S":"";
	
	return "$num" unless $subnum;
	
	"$num,$subnum"
}
sub ref_post_id($$){
	my($num,$subnum)=(@_,0);
	my($shadow)=$ghost_mode?"S":"";
	
	return "$num" unless $subnum;
	
	"${num}_$subnum"
}
sub ref_thread($){
	my($num)=@_;
	my($shadow)=$ghost_mode?"S":"";
	
	"$self/thread/$shadow$num"
}
sub ref_page($;$$){
	my($pageno,$num,$subnum)=(@_);
	my($shadow)=$ghost_mode?"S":"";
	
	$num=~s/,/_/;
	
	return "$self/page/$shadow$pageno" unless $num;
	return "$self/page/$shadow$pageno#p$num" unless $subnum;
	
	"$self/page/$shadow$pageno#p${num}_$subnum"
}

sub compile_template($%){
	my ($str)=@_;
	my $code;
	
	my $skipping_whitespace=0;
	
	$str=~s/^\s+//;
	$str=~s/\s+$//;
	$str=~s/\n\s*/ /sg;

	while($str=~m!(.*?)(<(/?)(var|eval|const|if|else|elsif|loop|nonl)(?:|\s+(.*?))>(?=[^{])|$)!sg){
		my($html,$tag,$closing,$name,$args)=($1,$2,$3,$4,$5);
		
		$html=~s/(['\\])/\\$1/g;
		$html=~s/^\s*//sg,$skipping_whitespace=0 if $skipping_whitespace;
		
		$code.="\$res.='$html';" if length $html;
		
		
		if($tag){
			if($closing){
				if   ($name eq 'if'   )		{ $code.='}' }
				elsif($name eq 'loop' )		{ $code.='$$_=$__ov{$_} for(keys %__ov);}}' }
			} else{
				if   ($name eq 'var'  )		{ $code.='$res.=eval{'.$args.'};' }
				elsif($name eq 'eval' )		{ $code.='eval{'.$args.'};' }
				elsif($name eq 'const')		{ my $const=eval $args; $const=~s/(['\\])/\\$1/g; $code.='$res.=\''.$const.'\';' }
				elsif($name eq 'if'   )		{ $code.='if(eval{'.$args.'}){' }
				elsif($name eq 'elsif')		{ $code.='}elsif(eval{'.$args.'}){' }
				elsif($name eq 'else' )		{ $code.='}else{' }
				elsif($name eq 'loop' )		{ $code.='my $__a=eval{'.$args.'};if($__a){for(@$__a){my %__ov;my %__v;eval{%__v=%{$_}};for(keys %__v){$__ov{$_}=$$_;$$_=$__v{$_};}' }
				elsif($name eq 'nonl' )		{ $skipping_whitespace=1 }
			}
		}
	}

	eval <<'HERE'.$code.<<'THERE' or die "Template format error";
no strict;
sub {
	my $port=$ENV{SERVER_PORT}==80?"":":$ENV{SERVER_PORT}";
	my $absolute_self="http://$ENV{SERVER_NAME}$port$ENV{SCRIPT_NAME}";
	my ($path)=$ENV{SCRIPT_NAME}=~m!^(.*/)[^/]+$!;
	my $absolute_path="http://$ENV{SERVER_NAME}$port$path";
	my %__v=@_;my %__ov;for(keys %__v){$__ov{$_}=$$_;$$_=$__v{$_};}
	my $res;
HERE
	$$_=$__ov{$_} for(keys %__ov);
	return $res;
}
THERE
}

sub sendpage(@){
	print "Set-Cookie: ",new CGI::Cookie(-name=>'ghost',-value=>$ghost_mode?"yes":"",-expires=>'+3M'),"\n";
	
	print <<HERE,@_;
Content-type: text/html; charset=utf-8

HERE
}

sub sendtext(@){
	print <<HERE,@_;
Content-type: text/plain; charset=utf-8

HERE
}

sub redirect($){
	my($location)=@_;
	print <<HERE and exit;
Status: 301
Location: $location
Content-Type: text/html; charset=utf-8

<html><body><a href=$location>$location</a></body></html>
HERE
}

my @time_scale=(
	[qw| 60	second	seconds	|],
	[qw| 60	minute	minutes	|],
	[qw| 24	hour	hours	|],
	[qw| 30	day		days	|],
	[qw| 12	month	months	|],
	[qw| 1000 year	years	|],
);

sub time_period_before($;$){
	my($time,$skip)=@_;

	return "VERY SOON!" if $time<=0;

	return "in ".time_period($time,$skip);
}

sub time_period_after($;$){
	my($time,$skip)=@_;

	return "very recently" if $time<=0;

	return time_period($time,$skip)." ago";
}

sub time_period($;$){
	my($time,$skip)=@_;
	my $res="";
	my @list;
	
	return "0 seconds" if $time<=0;
	
	for(@time_scale){
		my $count=$time % $_->[0];
		unshift @list,$count." ".($count==1?$_->[1]:$_->[2])
			if $count;
		last unless int($time/=$_->[0]);
		$time=int($time+0.5);
	}
	while($skip--){
		pop @list unless @list==1;
	}
	join " ",@list;
}

sub present_posts(@){
	my %res=map{
		$_->{subnum}?$_->{num}.'_'.$_->{subnum}:$_->{num},1
	} @_;
	
	\%res
}

sub fix_threads($){
	my($ref)=@_;
	
	for my $thread(@$ref){
		my @posts;
		my($head,@rest)=(shift @{$thread->{posts}},@{$thread->{posts}});
		while(@rest>5){
			$thread->{count}++;
			shift @rest;
		}
		my $present_posts=present_posts $head,@rest;
		for my $post($head,@rest){
			push @posts,fix_post($post,$present_posts);
		}
		
		$thread->{posts}=\@posts;
	}
	
	$ref;
}

sub fix_thread($){
	my($thread)=@_;
	
	use Data::Dumper;
	my $present_posts=present_posts @{$thread->{posts}};
	
	for my $post(@{$thread->{posts}}){
		$post=fix_post($post,$present_posts);
	}
	
	$thread
}

sub fix_filename($){
	my($file)=@_;
	
	(my $server_file=$file)=~s!$loc!$server_loc!i or die;
	
	$server_file
}

sub fix_post($$){
	my($post,$present_posts)=@_;
	
	my $file=$board->get_media_preview_location($post);
	
	(my $server_file=$file)=~s!$loc!$server_loc!i or die;
	
	$post->{file}=-f "$file"?
		"$server_file":
		"";

	$post->{comment}=format_comment($post->{comment},$present_posts);
	$post->{name}=html_encode($post->{name});
	$post->{title}=html_encode($post->{title});
	
	$post;
}

use constant ERROR_TEMPLATE => compile_template(NORMAL_HEAD_INCLUDE.<<'HERE'.NORMAL_FOOT_INCLUDE);
<div class="error container">
<t>
<h2>Error!</h2>
<t>
<ul>
<loop $cause>
	<li><var $_></li>
</loop>
</t>
</ul>
</t>
</div>
HERE


sub error(@){
	sendpage ERROR_TEMPLATE->(
		cause=>[map{map{html_encode $_}split /\n/,$_}@_],
	);
	exit;
}
	
use constant LATE_REDIECT_TEMPLATE	=> compile_template(CENTER_HEAD_INCLUDE.LATE_REDIRECT_INCLUDE.CENTER_FOOT_INCLUDE);
use constant INDEX_TEMPLATE			=> compile_template(CENTER_HEAD_INCLUDE.INDEX_INCLUDE.CENTER_FOOT_INCLUDE);
use constant PAGE_TEMPLATE			=> compile_template(NORMAL_HEAD_INCLUDE.SIDEBAR_INCLUDE.POSTS_INCLUDE.NORMAL_FOOT_INCLUDE);
use constant THREAD_TEMPLATE		=> compile_template(NORMAL_HEAD_INCLUDE.SIDEBAR_INCLUDE.POSTS_INCLUDE.NORMAL_FOOT_INCLUDE);
use constant SEARCH_PAGE_TEMPLATE	=> compile_template(NORMAL_HEAD_INCLUDE.SIDEBAR_INCLUDE.SEARCH_INCLUDE.NORMAL_FOOT_INCLUDE);
use constant ADV_SEARCH_TEMPLATE	=> compile_template(NORMAL_HEAD_INCLUDE.SIDEBAR_ADVANCED_SEARCH.NORMAL_FOOT_INCLUDE);

use constant REPORT_LIST_TEMPLATE	=> compile_template(NORMAL_HEAD_INCLUDE.SIDEBAR_INCLUDE.REPORT_LIST_INCLUDE.NORMAL_FOOT_INCLUDE);
use constant REPORT_THUMBS_TEMPLATE	=> compile_template(NORMAL_HEAD_INCLUDE.SIDEBAR_INCLUDE.REPORT_HEADER_INCLUDE.REPORT_THUMBS_INCLUDE.NORMAL_FOOT_INCLUDE);
use constant REPORT_TABLE_TEMPLATE	=> compile_template(NORMAL_HEAD_INCLUDE.SIDEBAR_INCLUDE.REPORT_HEADER_INCLUDE.REPORT_TABLE_INCLUDE.NORMAL_FOOT_INCLUDE);
use constant REPORT_GRAPH_TEMPLATE	=> compile_template(NORMAL_HEAD_INCLUDE.SIDEBAR_INCLUDE.REPORT_HEADER_INCLUDE.REPORT_GRAPH_INCLUDE.NORMAL_FOOT_INCLUDE);


sub redirect_late($$){
	my($title,$link)=@_;
	my($list)=MESSAGES;
	my $message=$list->[rand @$list];
	
	my $height=scalar(my @list=$message=~/\n/gs);

	print <<HERE,LATE_REDIECT_TEMPLATE->(
Content-type: text/html; charset=utf-8
Refresh: 2;url=$link

HERE
		title		=> $title,
		link		=> $link,
		
		height		=> $height+17,
		width		=> 60,
		
		message		=> $message,
		
		custom_css	=> <<HERE,
.outer { text-align: center; }
.inner { margin: auto; display: table; display: inline-block; text-decoration: none; text-align: left; padding:1em; border: thin dotted; }
.aa { font-family:Mona,'MS PGothic' !important; }
h1 { font-family: Georgia, serif; margin: 0 0 0.4em 0; font-size: 4em; text-align: center; }
p { margin-top: 2em; text-align:center; font-size: small; }
a { color:#34345c; }
a:visited { color:#34345c; }
a:hover { color:#DD0000; }
HERE
	);
	
	exit;
}

#
#
#

sub show_index(){
	sendpage INDEX_TEMPLATE->(
		list		=> [map{ {
			name				=> "$_",
			description			=> $board_desc,
			link				=> "$ENV{SCRIPT_NAME}/$_",
			
		} } @boards],
		
		title		=> "Yotsuba archiver",
		
		height		=> 18,
		width		=> 60,
	
		custom_css	=> <<HERE,
body {
	font-family: Georgia, serif;
}
h1 {
	margin: 0.1em;	
	text-align: center;
}
h2 {
	margin: 0.1em 0.1em 1em 0.1em;
	text-align: center;
}
p {
	margin: 0;
	font-size: 8em;
	text-align: center;
}
a, a:visited, a:hover{
	padding: 0.04em;
	color: #34345C;
	text-decoration: none;
}
a:hover {
	font-weight: bold;
	color: yellow;
	background: #DD0000;
	border: 4px solid yellow;
}
HERE
	);
	exit;
}

sub add_reply($$$$$$){
	my($name,$email,$subject,$comment,$parent,$delpass)=@_;
	my $nokoru=0;
	
	$name||='Anonymous';
	
	error "Abnormal reply (this is a mistery!)" if
		$parent=~/[^0-9]/	or
		length($parent)>12;
		
	# check for excessive amounts of text
	error "Field too long" if
		length($name)>MAX_FIELD_LENGTH		or
		length($email)>MAX_FIELD_LENGTH		or
		length($subject)>MAX_FIELD_LENGTH;
	
	error "Comment too long" if
		length($comment)>MAX_COMMENT_LENGTH;
	
	error "Too many lines in comment (you can only have ".MAX_COMMENT_LINES.")" if
		(split /\n/,$comment)>MAX_COMMENT_LINES;
	
	# check for empty reply or empty text-only post
	error "You didn't write a reply!?"
		if $comment=~/^\s*$/;
	
	# check for special bbcode tags no one is allwed to use
	error "You can't use that tag"
		if $comment=~/\[banned\]/;
	
	my $no_email_cookie=($email eq 'noko' or $email eq 'sage');
	$email='',$nokoru=1 if $email eq 'noko';
	
	$email=~s/^mailto://;

	if($delpass eq ''){
		my(@chars)=('a'..'z','A'..'Z','0'..'9');
		$delpass=join "",map{$chars[rand @chars]}1..12;
	}

	my $num=$board->post(
		name		=> $name,
		email		=> $email,
		title		=> $subject,
		comment		=> $comment,
		parent		=> $parent,
		date		=> yotsutime,
		id			=> $id,
		password	=> $delpass,
	);
	
	error $board->errstr if $board->error;
	
	print "Set-Cookie: ",new CGI::Cookie(-name=>'name',		-value=>$name,		-expires=>'+3M'),"\n" unless $no_email_cookie;
	print "Set-Cookie: ",new CGI::Cookie(-name=>'email',	-value=>$email,		-expires=>'+3M'),"\n";
	print "Set-Cookie: ",new CGI::Cookie(-name=>'delpass',	-value=>$delpass,	-expires=>'+3M'),"\n";
	
	redirect_late "That was VIP quality!",$nokoru?ref_post_far $num:ref_page 1,$num;
}

sub show_page($){
	my($pageno)=(@_);
	
	$pageno="S$pageno" if $ghost_mode and $pageno!~/^S/;
	
	my $page=$board->content(PAGE $pageno);
	
	$pageno=~s/^S//;

	sendpage PAGE_TEMPLATE->(
		title		=> ($pageno>1)?"Page $pageno":"",
		
		threads		=> fix_threads($page->{threads}),
		page		=> $pageno,
		thread		=> "",
		
		cgi_params,
	);
}

sub show_thread($){
	my($num)=(@_);
	
	$num=~/^\d+$/ and $num>0 or error "You didn't enter the thread number?!";
	
	my $thread=$board->content(THREAD $num);
	
	sendpage THREAD_TEMPLATE->(
		threads		=> [fix_thread($thread)],
		page		=> 0,
		thread		=> $num,
		
		replyform	=> 1,
		
		cgi_params,
	);
}

sub show_search($$$){
	my($text,$offset,$advanced)=@_;
	
#	error "Too bad. Database doesn't support searching for words with length less than 4"
#		if $text and length $text<=3;
	
	my $del=$cgi->param("search_del");
	my $int=$cgi->param("search_int");
	
	my @list=$board->search($text,24,$offset,$advanced?(
		name		=> ($cgi->param("search_username") or ""),
		trip		=> ($cgi->param("search_tripcode") or ""),
		showdel		=> ($del eq 'yes' or $del eq 'dontcare'),
		shownodel	=> ($del eq 'no' or $del eq 'dontcare'),
		showint		=> ($int eq 'yes' or $int eq 'dontcare'),
		showext		=> ($int eq 'no' or $int eq 'dontcare'),
		ord			=> ($cgi->param("search_ord") or ""),
	):());
	
	error $board->errstr if $board->error;
	
	sendpage SEARCH_PAGE_TEMPLATE->(title=>"Search: $text".($offset and ", offset: $offset" or ""),
		cgi_params,
		
		threads			=> [{posts=>[map{
			fix_post($_,{});
			$_->{ref}=($_->{parent} or $_->{num});
			$_->{blockquote}=1;
			$_
		}@list]}],
		
		found			=> scalar @list,
		
		search_inc		=> 24,
		search_pages	=> [map{my $diff=$_-$offset;{val=>$_,caption=>sprintf "%s%d",$diff<0?"-":"+",abs $diff}} grep{$_>=0} $offset-96,$offset-48,$offset-24,$offset+24,$offset+48,$offset+96],
	);
}

sub show_reports(){
	my @reports;
	my $loc=REPORTS_LOCATION;
	
	opendir DIRHANDLE,$loc or error "$! - $loc";
	while($_=readdir DIRHANDLE){
		next unless -f "$loc/$_";
		my %opts;
		
		open HANDLE,"$loc/$_" or error "$! - $loc/$_";
		for(<HANDLE>){
			/([\w\d\-]*)\s*:\s*(.*)/ or error "wrong report file format: $_";
			
			$opts{lc $1}=$2;
		}
		close HANDLE;
		
		error "$loc/$_: wrong format: must have field $_"
			foreach grep{not $opts{$_}} "query","mode","refresh-rate";
		
		$opts{filename}=$_;
		push @reports,\%opts;
	}
	closedir DIRHANDLE;

	sendpage REPORT_LIST_TEMPLATE->(title=>"reports",
		reports		=> \@reports,
		
		page		=> 0,
		thread		=> 0,
	);
}

sub get_report($){
	my($name)=@_;
	my $loc=REPORTS_LOCATION;
	my $imgloc=IMAGES_LOCATION;
	my %opts;
	
	open HANDLE,"$loc/$name" or error "$! - $loc/$name";
	for(<HANDLE>){
		/([\w\d\-]*)\s*:\s*(.*)/ or error "wrong report file format: $name";
		
		$opts{lc $1}=$2;
	}
	close HANDLE;
	die "$loc/$name: wrong format: must have field $_"
		foreach grep{not $opts{$_}} "query","mode","refresh-rate";

	if($opts{mode} eq 'graph'){
		$opts{'result-location'}="$imgloc/graphs";
		$opts{'result'}="$name.png";
	} else{
		$opts{'result-location'}="$loc/status";
		$opts{'result'}=$name;
	}

	%opts
}

sub show_report($){
	my($name)=@_;
	my(%opts)=get_report $name;

	my $time=mtime "$opts{'result-location'}/$board_name/$opts{'result'}";
	
	goto skip_messing_with_text_data if $opts{mode} eq 'graph';
	
	open HANDLE,"$opts{'result-location'}/$board_name/$opts{'result'}" or error "$! - $opts{'result-location'}/$board_name/$opts{'result'}";
	<HANDLE>;
	my @list=map{
		[map{s!^\s*!!;s!\s*$!!;$_}split /\|/,$_]
	}<HANDLE>;
	close HANDLE;

	my @rowtypes=split /,/,$opts{"row-types"};
	my @rownames=split /,/,$opts{"rows"};

	my @entries=map{
		my $num=0;
		my $ref=[];
		my $list=$_;
		while($num<@rowtypes){
			for($rowtypes[$num]){
				/^image$/ and do{
					my($preview,$num,$subnum,$parent,$media_hash)=
						(shift @$list,shift @$list,shift @$list,shift @$list,shift @$list);
					
					push @$ref,{
						name	=> $rownames[$num],
						file	=> fix_filename($board->get_media_preview_location(($parent or $num),$preview)),
						hash	=> $media_hash,
						type	=> "thumb",
					};
					next;
				};
				/^(text|code)$/ and do{
					push @$ref,{
						name	=> $rownames[$num],
						text	=> shift @$list,
						type	=> "text",
						subtype	=> "$1",
					};
					next;
				};
				/^timediff$/ and do{
					push @$ref,{
						name	=> $rownames[$num],
						text	=> ucfirst time_period_after(yotsutime-(shift @$list),6),
						type	=> "text",
					};
					next;
				};
				/^fromto$/ and do{
					my($avg,$std,$avgp,$stdp)=
						(shift @$list,shift @$list,shift @$list,shift @$list);
					
					my($start,$end)=map{
						$_=($_+86400)%86400;
						sprintf "%02d:%02d",$_/3600,int($_/60)%60
					} $stdp<$std?($avgp-$stdp,$avgp+$stdp):($avg-$std,$avg+$std);
					
					push @$ref,{
						name	=> $rownames[$num],
						text	=> qq{$start - $end},
						type	=> "text",
					};
					next;
				};
				/^postno$/ and do{
					my($num,$subnum)=
						(shift @$list,shift @$list);
					push @$ref,{
						name	=> $rownames[$num],
						text	=> qq{<a href="}.ref_post_far($num,$subnum).qq{">&gt;&gt;$num</a>},
						type	=> "text",
					};
					next;
				};
				/^username$/ and do{
					my($name,$trip)=
						(shift @$list,shift @$list);
					
					$name=(substr $name,0,61)."..."
						if length $name>64;
					
					push @$ref,{
						name	=> $rownames[$num],
						text	=> qq{<span class="postername">$name</span><span class="postertrip">$trip</span>},
						type	=> "text",
					};
					next;
				};
				/^skip$/ and shift @$list;
			}
			$num++;
		}

		{values=>$ref};
	}@list;
	
skip_messing_with_text_data:
	$opts{$_}=html_encode $opts{$_} foreach keys %opts;
	
	my $template;
	$template=REPORT_THUMBS_TEMPLATE if $opts{mode} eq 'thumbs';
	$template=REPORT_TABLE_TEMPLATE if $opts{mode} eq 'table';
	$template=REPORT_GRAPH_TEMPLATE if $opts{mode} eq 'graph';

	die unless $template;
	
	$opts{query}=~s/%%BOARD%%/$board_name/g;
	$opts{query}=~s/%%NOW%%/yotsutime/ge;

	sendpage $template->(
		%opts,
		entries		=> \@entries,
		rows		=> \@rownames,
		
		name		=> $name,
		
		last		=> time-$time,
		next		=> $opts{"refresh-rate"}-(time-$time),
		
		page		=> 0,
		thread		=> 0,
	);
}

#
#
#


our $task=$cgi->param("task");
$task="delete" if $cgi->param("delposts");
if($task){for($task){
	/^reply$/ and do{
		my($name,$email,$subject,$comment,$parent,$delpass)=
			map{$cgi->param($_)} qw/name email subject comment parent delpass/;
		
		add_reply($name,$email,$subject,$comment,$parent,$delpass);
	},exit;
	/^delete$/ and do{
		my(@postnums)=$cgi->param('delete');
		my($pass)=$cgi->param('delpass');
		my($succ)=0;
		
		for(@postnums){
			$board->delete($_,$pass,$id);
			error $board->errstr if $board->error;
			
			$succ++;
		}
		
		redirect_late "That was VIP quality!",ref_page 1;
	},exit;
	/^thread$/ and do{
		my $num=int $cgi->param("num");
		show_thread($num);
		exit;
	};
	/^page$/ and do{
		my $page=$cgi->param("page");
		
		show_page($page);
		exit;
	};
	/^post$/ and do{
		my($num)=$cgi->param("post")=~/.*(?:^|\D)(\d+)/;
		
		int $num or error "Please enter a post number";
		
		my $post=$board->content(POSTNO $num);
		$board->error and error $board->errstr;

		my($thread)=($post->{parent} or $post->{num});
		redirect ref_post $thread,$post->{num},$post->{subnum};
	};
	/^reports$/ and do{
		my($name)=$cgi->param("name");
		
		show_reports and exit unless $_;
		
		show_report($_);
		exit;
	};
	/^search(2)?$/ and do{
		my($text)=$cgi->param("search_text");
		my($offset)=$cgi->param("offset");
		my($advanced)=$1;
		
		show_search $text,$offset,$advanced;
		exit;
	};
	/^redirect?$/ and do{
		my($link)=$cgi->param("link");
		
		redirect $link;
	},exit;
	
	error "unknown task: $task";
}}

if($path){
	local($_)=$path;
	m!^/page/(.*)!x and do{
		my($page)=$1;
		
		show_page($page);
		exit;
	};
	m!^/thread/S?(.*)!x and do{
		my($num)=int $1;
		
		show_thread($num);
		exit;
	};
	m!^/advanced-search!x and do{
		sendpage ADV_SEARCH_TEMPLATE->(
			title		=> "Advanced search",
			
			height		=> 24,
			width		=> 40,
			
			standalone	=> 1,
		);
	},exit;
	m!^/post/S?(.*)!x and do{
		my($num)=$1;
		$num=~s/_/,/g;
		
		my $post=$board->content(POSTNO $num);
		ref $post or error $board->errstr;
		my($thread)=($post->{parent} or $post->{num});
		
		redirect ref_post $thread,$post->{num},$post->{subnum};
	};
	m!^/reports?(?:/(.*))?!x and do{
		my($name)=$1;
		
		show_reports and exit unless $name;
		
		show_report($name);
		exit;
	};
	m!^/image/(.*)! and do{
		my($val)=$1;
		
		print <<HERE;
Content-type: text/plain

hash: $val
there will more info here soon (probably!)
HERE
		
		exit;
	};
	m!^/actions?/([^/]*)/(.*)?!x and do{
		my($act,$args)=($1,$2);
		error "You are trying to do dangerous things" unless $ENV{REMOTE_ADDR} eq '127.0.0.1';

		for($act){
		/^update-report$/ and do{
			my(%opts)=get_report $args;
			
			utime 0, 0, "$opts{'result-location'}/$board_name/$opts{'result'}";
			redirect "$self/report/$args";
		};
		}

		die "($act,$args)";
		exit;
	};
}

show_page(1);