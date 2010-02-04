#!/usr/bin/perl

use strict;
use warnings;
use threads;
use threads::shared;
use Carp qw/confess/;
use Data::Dumper;
use Board::Request;
use Board::Errors;
use Board::Yotsuba;
use Board::Mysql;
$|++;

BEGIN{require "board-config.pl"}
my $board_name=shift or usage();
(my $settings=BOARD_SETTINGS->{$board_name}) or die "Can't archive $board_name until you add it to board-config.pl";

my $board_spawner=sub{Board::Yotsuba->new($board_name,timeout=>12) or die "No such board: $board_name"};

sub usage{
	print <<HERE;
Usage: $0 BOARD_NAME
Run this program to start archiving BOARD_NAME to mysql table BOARD_NAME.
HERE
	exit 1;
}

my $panic:shared;
$SIG{__DIE__}=sub{$panic=1};

my @thread_updates:shared;
my @media_updates:shared;
my @media_preview_updates:shared;
my %threads:shared;
my %busythreads:shared;
my @newthreads:shared;
my $debug_level=100;

use constant ERROR		=> 1;
use constant WARN		=> 2;
use constant TALK		=> 3;
sub debug($@){
	my $level=shift;
	print "[",
			scalar keys %threads," ",
			scalar @newthreads," ",
			scalar @thread_updates," ",
			scalar @media_updates," ",
			scalar @media_preview_updates," ",
			"] ",@_,"\n"
		if $level-1<$debug_level;
}

sub find_post($$){
	my($ref,$num)=@_;
	
	for(@{$ref->{posts}}){
		return $_ if $_->{num}==$num;
	}
}

sub update_thread($){
	my($thread)=@_;
	
	return unless $thread->{posts};
	
	my(@posts)=@{$thread->{posts}};

	if($settings->{"media-threads"}){
		$_->{preview} and push @media_preview_updates,shared_clone($_)
 			foreach @posts;
	}
	if($settings->{"media-threads"}){	
		$_->{preview} and push @media_preview_updates,shared_clone($_)
			foreach @posts;
	}

	push @thread_updates,$thread;
}

sub mark_deletes($$){
	my($old,$new)=@_;
	my $changed=0;
	
	return unless $old and $old->{ref}->{posts};
	
	my(@posts)=grep{not $_->{deleted}} @{$old->{ref}->{posts}};
	
	return unless @posts;
	
	my $dst=0;
	my $st=sub{
	return if $dst;
	$dst=1;
	print "old thread: ",(join ", ",map{$_->{num}}@posts),"\n";
	print "new thread: ",(join ", ",map{$_->{num}}@{$new->{posts}})," (",$new->{omposts}," posts omitted)\n";
	print "fixed thread: ",(join ", ",map{$_->{num}}@posts[0,$new->{omposts}+1..$#posts]),"\n";
	};
	
	foreach(@posts[0,$new->{omposts}+1..$#posts]){
		if((not $_->{deleted}) and not find_post $new,$_->{num}){
			$changed=1;
			$_->{deleted}=1;
			# $st->();
			push @{ $new->{posts} },$_;
			print "post $_->{num} was deleted\n";
		}
	}
	
	$changed
}

# fetch thumbs
async{my $board=$board_spawner->();my $local_board=SPAWNER->($board_name);while(1){
	my $ref;
	{	lock @media_preview_updates;
		$ref=shift @media_preview_updates;
	}
	
	sleep 1 and next unless $ref;
	
	$local_board->insert_media_preview($ref,$board);
		
	debug ERROR,"Couldn't insert posts into $local_board: ".$board->errstr
		and next if $local_board->error;
}} foreach 1..$settings->{"thumb-threads"};

# fetch pics
async{my $board=$board_spawner->();my $local_board=SPAWNER->($board_name);while(1){
	my $ref;
	{	lock @media_updates;
		$ref=shift @media_updates;
	}
	
	sleep 1 and next unless $ref;
	
	$local_board->insert_media($ref,$board);
		
	debug ERROR,"Couldn't insert posts into $local_board: ".$board->errstr
		and next if $local_board->error;
}} foreach 1..$settings->{"media-threads"};

# insert updates into database
async{my $local_board=SPAWNER->($board_name);while(1){
	while(my $ref=pop @thread_updates){
		$local_board->insert($ref);
		
		debug ERROR,"Couldn't insert posts into database: ".$local_board->errstr
			if $local_board->error;
	}
	sleep 1;
}};

# scan pages
async{
	my $board=$board_spawner->();
	my($pagenos,$wait)=@$_;
	while(1){
		my $now=time;
		
		foreach my $pageno(@$pagenos){
			my $list=$board->content(PAGE $pageno);
			sleep 1 and print $board->errstr,"\n" and next if $board->error;
			
			for(@{$list->{threads}}){
				my $num=$_->{num};
				push @newthreads,$num and next unless $threads{$num};
				
				my $thread=$threads{$num};
				my(@posts)=@{$_->{posts}};
				
				my($old,$new,$must_refresh)=(0,0,0);
				
				mark_deletes $thread,$_ and $must_refresh=1;
				
				for(@posts){
					my $post=find_post($thread->{ref},$_->{num});
					
					# Comment too long. Click here to view the full text.
					$must_refresh=1 if $_->{omitted};
					
					# this post already is in %threads
					$post and ++$old and next;
					
					# is not
					push @{$thread->{ref}->{posts}},shared_clone($_);
					$new++;
					
					$must_refresh=1 if $_->{media};
				}
				
				$thread->{lasthit}=time;
				
				# no new posts
				next if $old!=0 and $new==0;
				
				debug TALK,"$_->{num}: ".($pageno==0?"front page":"page $pageno")." update";
				
				update_thread $thread->{ref};
				push @newthreads,$num if $must_refresh or $old<2;
			}
		}
		my $left=$wait-(time-$now);
		sleep $left if $left>0;
	}
} foreach @{ $settings->{pages} };

# rebuild whole thread, either because it's new or because it's too old
async{my $board=$board_spawner->();while(1){
	use threads;
	use threads::shared;

	local $_;
	{	lock @newthreads;
		$_=shift @newthreads;
	}
	
	sleep 1 and next unless $_ and /^\d+$/;
	
	{	lock %busythreads;
		next if $busythreads{$_};
		$busythreads{$_}=1;
	}
	
	my $gettime=time;
	my $thread=$board->content(THREAD $_);
	if($board->error){
		debug WARN,"$_: error: ",$board->errstr;
		
		# if thread is no more than 1 hour old, it was forcefully deleted
		if($board->errstr eq 'Not Found' and $threads{$_} and
				yotsutime-$threads{$_}->{ref}->{posts}->[0]->{date}<60*60){
			$threads{$_}->{ref}->{posts}->[0]->{deleted}=1;
			
			debug TALK,"$_: deleted";
			update_thread $threads{$_}->{ref};
		}
		
		delete $threads{$_};
		
		goto finished;
	}
	
	# This is silly
	# Sometimes when refreshig thread it takes too much time to get it,
	# it gets updated from front page, resulting in all new posts being marked
	# as deleted.
	# This is silly.
	# Reminder to myself: do something about this.
	goto finished if $threads{$_} and $threads{$_}->{lasthit}>$gettime;
	
	debug TALK,"$_: ".($threads{$_}?"updated":"new");
	
	mark_deletes $threads{$_},$thread;
	$threads{$_}=shared_clone({
		num		=> $_,
		lasthit	=> time,
		ref		=> $thread,
	});
	
	update_thread $threads{$_}->{ref};

finished:
	{	lock %busythreads;
		delete $busythreads{$_};
	}
}} foreach 1..$settings->{"new-thread-threads"};

# check for old threads to rebuild
while(1){
	my $now=time;
	for(keys %threads){
		my $thread=$threads{$_};
		my $lasthit=$now-$thread->{lasthit};
		
		next unless $lasthit>$settings->{"thread-refresh-rate"}*60;
		next if $thread->{remaking};
		
		$thread->{remaking}=1;
		push @newthreads,$_;
	}
	
	exit if $panic;
	sleep 1;
}
