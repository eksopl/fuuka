#!/usr/bin/perl

use strict;
use warnings;
use threads;
use threads::shared 1.21;

use Carp qw/confess/;
use Data::Dumper;

use Board::Request;
use Board::Errors;
use Board::Yotsuba;
use Board::Mysql;
use Board::Sphinx_Mysql;
$|++;

BEGIN{-e "board-config-local.pl" ? require "board-config-local.pl" : require "board-config.pl"}
my $board_name=shift or usage();
my $bind_ip=shift;
(my $settings=BOARD_SETTINGS->{$board_name}) or die "Can't archive $board_name until you add it to board-config.pl";

my $board_spawner=sub{Board::Yotsuba->new($board_name,timeout=>12,ipaddr=>$bind_ip) or die "No such board: $board_name"};

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

# Receives a thread reference and a post num.
# The post corresponding to that num if it exists in said thread.
sub find_post($$){
	my($ref,$num)=@_;
	
	for(@{$ref->{posts}}){
		return $_ if $_->{num}==$num;
	}
}

# Receives a thread.
# For each post that has an image, put it in the queue to fetch
# images/thumbs.
# Then place the thread itself in the queue for thread updating.
sub update_thread($){
	my($thread)=@_;
	
	return unless $thread->{posts};
	
	my(@posts)=@{$thread->{posts}};

	if($settings->{"thumb-threads"}){
		$_->{preview} and push @media_preview_updates,shared_clone($_)
 			foreach @posts;
	}
	if($settings->{"media-threads"}){	
		$_->{media_filename} and push @media_updates,shared_clone($_)
			foreach @posts;
	}

	push @thread_updates,$thread;
}

# Gets two threads, the old thread and the new one we just got.
# Returns: 1 if there's been a change in the deletion status of any post in the new thread.
#          0 otherwise.
sub mark_deletes($$){
	my($old,$new)=@_;
	my $changed=0;

	# Return if the old thread has no posts	
	return unless $old and $old->{ref}->{posts};
	
	# Get the posts from the old thread not marked as deleted.
	# (no point on getting the deleted ones, we'd just end up marking them as deleted twice)
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
			debug TALK,"$_->{num} (post): deleted";
		}
	}
	
	$changed
}

# fetch thumbs
async{my $board=$board_spawner->();my $local_board=SPAWNER->($board_name);while(1){
	my $ref;
	{
		lock @media_preview_updates;
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
	{
		lock @media_updates;
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

# Scan pages
async{
	my $board=$board_spawner->();

	# $pagenos is a list with the page numbers
	# $wait is the refresh time for those pages
	# %lastmods contains last modification dates for each page
	my($pagenos,$wait)=@$_;
	my %lastmods;
	while(1){
		my $now=time;
	
		# Scan through pages with the same wait period	
		foreach my $pageno(@$pagenos){
			# If there's a lastmod in the lastmods hash, we pass it to content()...
			my $lastmod = defined $lastmods{$pageno} ? $lastmods{$pageno} : undef;
			my $list=$board->content(PAGE($pageno,$lastmod));

			# ...and then we store the lastmod date for the page we just got
			$lastmods{$pageno} = $list->{lastmod};

			# Just move on if it hasn't been modified
			next if $board->error and  $board->errstr eq 'Not Modified';
			sleep 1 and print $board->errstr,"\n" and next if $board->error;
	
			# Scan through threads on that page
			for(@{$list->{threads}}){
				my $num=$_->{num};

				# Push thread into new threads queue and skips
				# if we haven't seen it before
				push @newthreads,$num and next unless $threads{$num};
				
				# Otherwise we get the thread we had already
				# previously seen
				my $thread=$threads{$num};
				my(@posts)=@{$_->{posts}};
				
				my($old,$new,$must_refresh)=(0,0,0);

				# We check for any posts that got deleted.
				mark_deletes $thread,$_ and $must_refresh=1;
				for(@posts){
					# Get the same post from the previous encountered thread
					my $post=find_post($thread->{ref},$_->{num});
					
					# Comment too long. Click here to view the full text.
					# This means we have to refresh the full thread
					$must_refresh=1 if $_->{omitted};
					
					# This post was already in %threads. Next post
					$post and ++$old and next;
					
					# If it's new, deep copies the thread into our thread hash
					push @{$thread->{ref}->{posts}},shared_clone($_);
					$new++;
					
					# We have to refresh to get the image filename, sadly
					$must_refresh=1 if $_->{media};
				}
				
				# Update the time we last hit this thread
				$thread->{lasthit}=time;
				
				# No new posts
				next if $old!=0 and $new==0;
				
				debug TALK,"$_->{num}: ".($pageno==0?"front page":"page $pageno")." update";
			
				# Push new posts/images/thumbs to their queues	
				update_thread $thread->{ref};
				
				# And send the thread to the new threads queue if we were
				# forced to refresh earlier or if the only old post we
				# saw was the OP, as that means we're missing posts from inside the thread.
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
	{
		lock @newthreads;
		$_=shift @newthreads;
	}
	
	sleep 1 and next unless $_ and /^\d+$/;
	
	{
		lock %busythreads;
		next if $busythreads{$_};
		$busythreads{$_}=1;
	}
	
	my $gettime=time;

	my $lastmod = defined $threads{$_} ? $threads{$_}->{ref}->{lastmod} : undef;
	my $thread=$board->content(THREAD($_, $lastmod)); 
	if($board->error){
		if($board->errstr eq 'Not Modified') {
			debug TALK,"$_: wasn't modified";
			$threads{$_}->{remaking} = 0;
			$threads{$_}->{lasthit} = time;
			goto finished;
		}
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
	# Sometimes when refreshing thread it takes too much time to get it,
	# it gets updated from front page, resulting in all new posts being marked
	# as deleted.
	# This is silly.
	# Reminder to myself: do something about this.
	goto finished if $threads{$_} and $threads{$_}->{lasthit}>$gettime;
	
	debug TALK,"$_: ".($threads{$_}?"updated":"new");

	mark_deletes $threads{$_},$thread;
	$threads{$_}=shared_clone({
		num		 => $_,
		lasthit	 => time,
		ref		 => $thread,
	});
	
	update_thread $threads{$_}->{ref};

finished:
	{
		lock %busythreads;
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
