package Board::WWW;

use strict;
use warnings;
use Carp qw/confess/;

use Board;
use Board::Errors;
our @ISA=qw/Board/;

use LWP::UserAgent;
use HTTP::Request::Common;

sub new{
	my $class=shift;
	my(%info)=@_;

	push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, "LocalAddr" => $info{ipaddr}) if $info{ipaddr};

	my $ua=LWP::UserAgent->new;
	$ua->agent(delete $info{agent} or "Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1)");
	$ua->proxy('http', "http://".($info{proxy})) if $info{proxy};
	$ua->timeout($info{timeout}) if $info{timeout};
	
	my $self=$class->SUPER::new(%info);
	
	$self->{agent}=$ua;
	$self->{proxy}=$info{proxy} if $info{proxy};
	
	bless $self,$class;
}

sub wget($$;$$){
	my($self,$link,$referer,$lastmod)=@_;
	my($res,$text);
	
	my $req=(GET $link);
	$req->referer($referer) if $referer;
	$req->accept_decodable() if $req->can('accept_decodable');
	$req->header("If-Modified-Since", $lastmod) if $lastmod;

	my $retrycount = 3;

MAINLOOP:
	$res=$self->{agent}->request($req);

	eval {
		local $SIG{__DIE__};
		$text=$res->decoded_content();
	} or do {
		$self->error(FORGET_IT,"Can't decode content"),return;
	};

	$self->error(0),return ($text,$res) if $res->is_success;
	my($no,$line)=$res->status_line=~/(\d+) (.*)/;
	($retrycount-- and goto MAINLOOP) if($no =~ /^500/ and $retrycount > 0);

	$self->error(FORGET_IT,$line);
}

sub wpost_ext($$$$%){
	my($self,$link,$referer,$contenttype,%params)=@_;
	my($res,$text);
	
	my $req=(POST $link, 
		Content_Type	=>$contenttype,
		Content			=>[%params],
	);
	$req->referer($referer) if $referer;
	

MAINLOOP:
	$res=$self->{agent}->request($req);
	$text=$res->content;
	
	$self->error(0),return $text if $res->is_success;
	my($no,$line)=$res->status_line=~/(\d+) (.*)/;
	for($res->status_line){
		/^500/ and $self->warn("www","$_") and goto MAINLOOP;
	}
	
	$self->error(FORGET_IT,$line);
}

sub wpost($$$%){
	my($self,$link,$referer,%params)=@_;
	$self->wpost_ext($link,$referer,'multipart/form-data;boundary=1',%params);
}

sub wpost_x_www($$$%){
	my($self,$link,$referer,%params)=@_;
	$self->wpost_ext($link,$referer,'application/x-www-form-urlencoded',%params);
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

1;
