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

BEGIN{-e "board-config-local.pl" ? 
	require "board-config-local.pl" : require "board-config.pl"}
my $board_name=shift or usage();
my $bind_ip=shift;
(my $settings=BOARD_SETTINGS->{$board_name}) 
	or die "Can't archive $board_name until you add it to board-config.pl";

my $board_spawner=sub{Board::Yotsuba->new($board_name,timeout=>12,ipaddr=>$bind_ip) 
	or die "No such board: $board_name"};

sub usage{
	print <<HERE;
Usage: $0 BOARD_NAME
Run this program to start archiving BOARD_NAME to mysql table BOARD_NAME.
HERE
	exit 1;
}

my $panic:shared;
$SIG{__DIE__}=sub{$panic=1};

my %threads:shared;
my @newthreads:shared;
my @thread_updates:shared;
my @media_updates:shared;
my @media_preview_updates:shared;
my @deleted_posts:shared;

my $debug_level=100;

use constant ERROR		=> 1;
use constant WARN		=> 2;
use constant TALK		=> 3;

use constant PAGELIMBO	=> 13;

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
	my($thread, $num) = @_;
	for(@{$thread->{allposts}}){
		return $_ if $_==$num;
	}
}

# Gets two threads, the old thread and the new one we just got.
# Returns: 1 if there's been a change in the deletion status of any post in the new thread
#		   0 otherwise
# If the third argument is false, it won't actually mark anything as deleted.
sub find_deleted($$$){
	my($old, $new, $mark) = @_;
	my $changed = 0;

	# Return if the old thread has no posts 
	return 0 unless $old and $old->{posts};
	
	my(@posts) = @{$old->{allposts}};
	
	return unless @posts;
	
	foreach(@posts[0, $new->{omposts}+1..$#posts]){
		my $post = $_;
		if(not find_post $new, $post) {
			return 1 if not $mark;
			
			$changed = 1;
			my @oldposts = grep { $_ != $post } @{$old->{allposts}};
			delete $old->{allposts} if defined $old->{allposts};
			$old->{allposts} = shared_clone(\@oldposts);
			
			push @deleted_posts, $post;
			debug TALK,"$post (post): deleted";
		}
	}
	
	$changed
}

# fetch thumbs
async{my $board=$board_spawner->();my $local_board=SPAWNER->($board_name);while(1) {
	my $ref;
	{
		lock @media_preview_updates;
		$ref=shift @media_preview_updates;
	}
	
	sleep 1 and next unless $ref;
	
	$local_board->insert_media_preview($ref, $board);
		
	debug ERROR,"Couldn't insert posts into $local_board: ".$board->errstr
		and next if $local_board->error;
}} foreach 1..$settings->{"thumb-threads"};

# fetch pics
async{my $board=$board_spawner->();my $local_board=SPAWNER->($board_name);while(1) {
	my $ref;
	{
		lock @media_updates;
		$ref = shift @media_updates;
	}
	
	sleep 1 and next unless $ref;
	
	$local_board->insert_media($ref, $board);
		
	debug ERROR,"Couldn't insert posts into $local_board: ".$board->errstr
		and next if $local_board->error;
}} foreach 1..$settings->{"media-threads"};

# insert updates into database
async{my $local_board=SPAWNER->($board_name);while(1){
	while(my $thread = pop @thread_updates) {
	{
		lock($thread);
		next if not $thread->{ref};
		
		$local_board->insert($thread->{ref});
		
		debug ERROR,"Couldn't insert posts into database: ".$local_board->errstr
			if $local_board->error;
			
		foreach(@{$thread->{ref}->{posts}}) {
			my $mediapost;
			if($_->{preview} or $_->{media_filename}) {
				$mediapost = shared_clone(bless {
					num			   => $_->{num},
					parent		   => $_->{parent},
					preview		   => $_->{preview},
					media_filename => $_->{media_filename},
					media_hash	   => $_->{media_hash}
				}, "Board::MediaPost");
			}
			push @media_preview_updates, $mediapost
				if $_->{preview} and $settings->{"thumb-threads"};
			push @media_updates, $mediapost
				if $_->{media_filename} and $settings->{"media-threads"};
		}

		delete $thread->{ref}->{posts};
		$thread->{ref}->{posts} = shared_clone([]);
	}
	}
	sleep 1;
}};

# Post Deleter
# mark posts as deleted
async{my $local_board=SPAWNER->($board_name);while(1){
	my $ref;
	{
		lock @deleted_posts;
		$ref = shift @deleted_posts;
	}
	
	sleep 1 and next unless $ref;
	
	$local_board->mark_deleted($ref);
		
	debug ERROR,"Couldn't update deleted status of post $ref: ".$local_board->errstr
		if $local_board->error;
	sleep 5;
}};

# Page Scanner
# Scan pages
async {
	my $board = $board_spawner->();

	# $pagenos is a list with the page numbers
	# $wait is the refresh time for those pages
	# %lastmods contains last modification dates for each page
	my($pagenos, $wait) = @$_;
	my %lastmods;
	while(1) {
		my $now = time;
	
		# Scan through pages with the same wait period	
		foreach my $pageno(@$pagenos){
			# If there's a lastmod in the lastmods hash, we pass it to content()...
			my $lastmod = defined $lastmods{$pageno} ? $lastmods{$pageno} : undef;
			my $starttime = time;
			my $list = $board->content(PAGE($pageno, $lastmod));

			# Just move on if it hasn't been modified
			if($board->error and $board->errstr eq 'Not Modified') {
				debug TALK, ($pageno == 0 ? "front page" : "page $pageno") 
					. ": wasn't modified";
				next;
			}
			sleep 1 and print $board->errstr,"\n" and next if $board->error;
			
			# ...and then we store the lastmod date for the page we just got
			delete $lastmods{$pageno};
			$lastmods{$pageno} = $list->{lastmod};
	
			# Scan through threads on that page
			for(@{$list->{threads}}) {
				my $num = $_->{num};

				# Push thread into new threads queue and skips
				# if we haven't seen it before
				push @newthreads, $num and next unless $threads{$num};
				
				# Otherwise we get the thread we had already
				# previously seen
				my $thread = ${$threads{$num}};
				lock $thread;
				next unless defined $threads{$num};
				
				my(@posts) = @{$_->{posts}};
				
				next if $thread->{lasthit} > $starttime;
				
				delete $thread->{lastpage};
				$thread->{lastpage} = $pageno;
				
				my($old, $new, $must_refresh) = (0, 0, 0);

				# We check for any posts that got deleted.
				if(find_deleted($thread->{ref}, $_, 0)) {
					$must_refresh = 1;
					++$new;
				}

				for(@posts){
					# This post was already in topics map. Next post
					++$old and next if find_post($thread->{ref}, $_->{num});
					
					# Looks like it's new
					++$new;
										
					# If it's new, deep copies the post into our thread hash
					push @{$thread->{ref}->{posts}}, shared_clone($_);
					push @{$thread->{ref}->{allposts}}, shared_clone($_->{num});
					
					# Comment too long. Click here to view the full text.
					# This means we have to refresh the full thread
					$must_refresh=1 if $_->{omitted};
										
					# We have to refresh to get the image filename, sadly
					$must_refresh=1 if $_->{media};
				}
				
				# Update the time we last hit this thread
				$thread->{lasthit}=time;
				
				# No new posts
				next if $old!=0 and $new==0;
				
				debug TALK, "$_->{num}: " . ($pageno == 0 ? "front page" : "page $pageno")
					. " update";
			
				# Push new posts/images/thumbs to their queues	
				push @thread_updates, $thread;
				
				# And send the thread to the new threads queue if we were
				# forced to refresh earlier or if the only old post we
				# saw was the OP, as that means we're missing posts from inside the thread
				if($must_refresh or $old < 2) {
					debug TALK, "$num: must refresh";
					push @newthreads, $num ;
				}
			}
		}
		my $left = $wait - (time - $now);
		sleep $left if $left > 0;
	}
} foreach @{$settings->{pages}};

# Topic Fetcher
# Rebuild whole thread, either because it's new or because it's too old
async{my $board=$board_spawner->();while(1){
	use threads;
	use threads::shared;

	local $_;
	{
		lock @newthreads;
		$_ = shift @newthreads;
	}
	
	my $num = $_;
	
	sleep 1 and next unless $_ and /^\d+$/;
	{
		my $oldthread = defined $threads{$num} ? ${$threads{$num}} : undef;
		lock($oldthread) if defined $oldthread;
		next if defined $oldthread and not defined $threads{$num};
				
		my $lastmod = defined $oldthread ? $oldthread->{ref}->{lastmod} : undef;
		my $starttime=time;
		my $thread = $board->content(THREAD($_, $lastmod)); 

		if($board->error){
			if($board->errstr eq 'Not Modified') {
				debug TALK,"$num: wasn't modified";
				if(defined $oldthread) {
					delete $oldthread->{lasthit};
					delete $oldthread->{busy};
					$oldthread->{lasthit} = time;
					$oldthread->{busy} = 0;
				}
			} elsif($board->errstr eq 'Not Found' and defined $oldthread) {
				if($oldthread->{lastpage} < PAGELIMBO) {
					push @deleted_posts, $oldthread->{ref}->{posts}->[0];
					debug TALK, "$num: deleted (last seen on page " 
						. $oldthread->{lastpage} . ")";
				}
				delete $oldthread->{ref};
				delete $threads{$num};
			} else {
				debug ERROR, "$num: error: ". $board->errstr;
			}
			next;
		}
		
		my $lastpage = 0;
		if(defined $oldthread) {
			next if $oldthread->{lasthit} > $starttime;
			find_deleted $oldthread->{ref}, $thread, 1;
			$lastpage = $oldthread->{lastpage};
			
			delete $oldthread->{ref};
			delete $oldthread->{lasthit};
			delete $oldthread->{busy};
			$oldthread->{ref} = shared_clone($thread);
			$oldthread->{lasthit} = $starttime;
			$oldthread->{busy} = 0;
		} else {
			my $newthread :shared = shared_clone({
				num		 => $num,
				lasthit  => $starttime,
				ref		 => $thread,
				lastpage => 0
			});
			$threads{$num} = \$newthread;
		}
		
		push @thread_updates, ${$threads{$num}};
		debug TALK, "$num: " . (${$threads{$num}} ? "updated" : "new");
	}
}} foreach 1..$settings->{"new-thread-threads"};

# Topic Rebuilder
# check for old threads to rebuild
while(1) {
	for(keys %threads) {
		my $thread = ${$threads{$_}};
		lock($thread);
		next unless defined $threads{$_};
		
		next if $thread->{busy};

		my $lasthit = time - $thread->{lasthit};
		
		next unless $lasthit > $settings->{"thread-refresh-rate"}*60;
		
		$thread->{busy} = 1;
		push @newthreads, $_;
	}

	exit if $panic;
	sleep 1;
}


# vim: set ts=4 sw=4 noexpandtab:

