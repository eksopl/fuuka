package Board::Mysql;

use strict;
use warnings;
use Carp qw/confess cluck/;
use DBI;

use Board::Local;
use Board::Errors;
our @ISA = qw/Board::Local/;

sub new($$;%){
	my $class=shift;
	my $path=shift;
	my(%info)=(@_);
	
	my $opts=[{@_},$path];
	
	my($tname)=$path=~/(\w+)$/;
	
	my $database	=(delete $info{database}	or "Yotsuba");
	my $table		=(delete $info{table}		or $tname or "proast");
	my $host		=(delete $info{host}		or "localhost");
	my $name		=(delete $info{name}		or "root");
	my $password	=(delete $info{password}	or "");
	my $connstr		=(delete $info{connstr}		or "");
	my $create_new	= delete $info{create};
	
	my $self=$class->SUPER::new($path,%info);
	
	my $dbh = DBI->connect(
		($connstr or "DBI:mysql:database=$database;host=$host"),
		$name,
		$password,
		{AutoCommit=>1,PrintError=>0,mysql_enable_utf8=>1},
	) or die $DBI::errstr;

	$self->{dbh}				= $dbh;
	$self->{table}				= $table;
	$self->{spam_table}			= "${table}_spam";
	$self->{threads_per_page}	= 20;
	$self->{opts}				= $opts;
	
	$self->_create_table if $create_new;

	bless $self,$class;
}

sub _create_table($){
	my $self=shift;

	$self->{dbh}->do(<<HERE);
create table if not exists $self->{table} (
	id int unsigned,
	num int unsigned not null,
	subnum int unsigned not null,
	parent int unsigned,
	timestamp int unsigned,
	preview text,
	preview_w smallint unsigned,
	preview_h smallint unsigned,
	media text,
	media_w smallint unsigned,
	media_h smallint unsigned,
	media_size INT unsigned,
	media_hash varchar(64),
	media_filename tinytext,

	spoiler bool,
	deleted bool,
	capcode enum('N', 'M', 'A', 'G') not null default 'N',

	email varchar(64),
	name varchar(256),
	trip varchar(64),
	title text,
	comment text,
	delpass tinytext,
	
	primary key (num,subnum),
	
	index id_index(id),
	index num_index(num),
	index subnum_index(subnum),
	index parent_index(parent),
	index timestamp_index(timestamp),
	index media_hash_index(media_hash),
	index email_index(email),
	index name_index(name),
	index trip_index(trip),
	index fullname_index(name,trip),
	fulltext index comment_index(comment)
) engine=myisam default charset=utf8;
HERE

$self->{dbh}->do(<<HERE);
	create table if not exists $self->{table}_local (
		num int unsigned not null,
		subnum int unsigned not null,
		timestamp int unsigned,
		parent int unsigned,
		primary key (parent),
		index timestamp_index(timestamp)
	) engine=myisam default charset=utf8;
HERE
}

sub _read_post($$){
	my $self=shift;
	my(	$id,$num,$subnum,$parent,$date,$preview,$preview_w,$preview_h,
		$media,$media_w,$media_h,$media_size,$media_hash,$media_filename,
		$spoiler,$deleted,$capcode,$email,$name,$trip,$title,$comment,$delpass
	)=@{ $_[0] };

	$self->new_post(
		media		=> $media,
		media_hash	=> $media_hash,
		media_filename=> $media_filename,
		media_size	=>($media_size or 0),
		media_w		=>($media_w or 0),
		media_h		=>($media_h or 0),
		preview		=> $preview,
		preview_w	=>($preview_w or 0),
		preview_h	=>($preview_h or 0),
		num			=> $num,
		subnum		=> $subnum,
		parent		=> $parent,
		title		=> $title,
		email		=> $email,
		name		=> $name,
		trip		=> $trip,
		date		=> $date,
		comment		=> $comment,
		password	=> $delpass,
		spoiler		=> $spoiler,
		deleted		=> $deleted,
		capcode		=> $capcode,
		userid		=> $id,
	)
}

sub _read_thread($@){
	my $self=shift;
	my($list)=@_;

	my $t=$self->new_thread(
		omposts		=> 0,
		omimages	=> 0,
		posts		=> [],
	);
	
	for my $ref(@$list){
		my($post)=$self->_read_post($ref);
		
		push @{$t->{posts}},$post;
		
		$t->{num}||=$post->{num};
	}
	
	$t;
}
sub get_post($$;$){
	my $self=shift;
	my($num)=(@_);
	($num,my $subnum)=((split /,/,$num),0);
	
	my($ref)=$self->query("select * from $self->{table} where num=? and subnum=?",$num,$subnum) or return;
	$ref->[0] or $self->error(FORGET_IT,"Post not found"),return;
	
	$self->ok;
	
	$self->_read_post($ref->[0]);
}

sub get_thread($$){
	my $self=shift;
	my($thread)=@_;

$self->_read_thread($self->query(<<HERE,$thread,$thread) or return);
select * from $self->{table} where num=? or parent=? order by num,subnum asc
HERE
}

sub get_page($$){
	my $self=shift;
	my($pagetext)=@_;
	
	my($shadow,$page)=$pagetext=~/^(S)?(\d+)$/;
	
	$page-=1;
	$page=0 if $page<0;
	
	my $p=$self->new_page($page);
	my @list;

	my @results=@{ $self->query($shadow?<<HERE:<<THERE,$self->{threads_per_page},$self->{threads_per_page}*$page) or return };
select * from $self->{table}, 
	(select parent from $self->{table}_local order by timestamp desc limit ? offset ?) as j 
	where $self->{table}.parent = j.parent or $self->{table}.num = j.parent;
HERE
select $self->{table}.* from
	(select num from $self->{table} where parent=0 order by num desc limit ? offset ?) as threads join $self->{table}
		on threads.num=$self->{table}.num or threads.num=$self->{table}.parent
			order by case parent when 0 then $self->{table}.num else parent end desc,num,subnum asc
THERE
	for my $ref(@results){
		my($id,$num,$subnum,$parent)=@$ref;
		
		unless($parent){
			push @{$p->{threads}},$self->_read_thread(\@list) if @list;
			@list=($ref);
		} elsif(@list){
			push @list,$ref;
		}
	}
	push @{$p->{threads}},$self->_read_thread(\@list) if @list;
	
	$self->ok;
	
	$p;
}

sub search($$$$){
	my $self=shift;
	my($text,$limit,$offset,%settings)=@_;
	my $dbh=$self->{dbh};
	
	$limit=int $limit;
	$offset=int $offset;
	
	my @conditions;
	my @index_hint;
	
	push @conditions,"name=".$dbh->quote($settings{name}) and
	push @index_hint,"name_index"
		if $settings{name};
	
	push @conditions,"trip=".$dbh->quote($settings{tripcode}) and
	push @index_hint,"trip_index"
		if $settings{tripcode};
	
	push @conditions,"media_hash=".$dbh->quote($settings{media_hash}) and
	push @index_hint,"media_hash_index"
		if $settings{media_hash};
	
	push @conditions,"deleted=1"
		if $settings{showdel} and not $settings{shownodel};
	
	push @conditions,"deleted=0"
		if $settings{shownodel} and not $settings{showdel};
	
	push @conditions,"subnum!=0"
		if $settings{showint} and not $settings{showext};
	
	push @conditions,"subnum=0"
		if $settings{showext} and not $settings{showint};
	
	my $ord=$settings{ord};
	my $query_ord="timestamp desc";
	
	$query_ord="timestamp asc" if $ord and $ord eq 'old';
	
	my $condition=join "",map{"$_ and "}@conditions;
	
	my $index_hint=@index_hint?
		"use index(".(join ",",@index_hint).")":
		"";
	
	my $query=(0 and $text and $ord eq 'rel' and $text!~/[\*\+\-]/)?
		"select *,match(comment) against(".
		$dbh->quote($text).
		") as score from $self->{table} $index_hint where $condition match(comment) against(".
		$dbh->quote(join " ",map{"+$_"}split /\s+/,$text).
		" in boolean mode) order by score desc, timestamp desc limit $limit offset $offset;":
		
		$text?
		"select * from $self->{table} $index_hint where $condition match(comment) against(".
		$dbh->quote($text).
		" in boolean mode) order by $query_ord limit $limit offset $offset;":
		
		"select * from $self->{table} $index_hint where $condition 1 order by $query_ord limit $limit offset $offset";
	
	my($ref)=($self->query($query) or return);
	
	map{$self->_read_post($_)} @$ref
}

sub post($;%){
	my $self=shift;
	my(%info)=@_;
	my($thread)=($info{parent} or die "can only post replies to threads, not create new threads");
	my $date=($info{date} or time);
	my($ref);
	
	$ref=$self->query("select count(*) from $self->{table} where id=? and timestamp>?",$info{id},$date-$self->{renzoku});
	$self->error(TRY_AGAIN,"You can't post that fast"),return
		if $ref->[0]->[0];
	
	$ref=$self->query("select count(*) from $self->{table} where id=? and timestamp>? and comment=?",$info{id},$date-$self->{renzoku3},$info{comment});
	$self->error(TRY_AGAIN,"You already posted that, cowboy!"),return
		if $ref->[0]->[0];
	
	($info{name},$info{trip})=$self->tripcode($info{name});
	
	$self->insert({
		%info
	}) or return;
	
	$ref=$self->query("select num,subnum from $self->{table} where id=? and timestamp=?",$info{id},$date) or return;
	
	$ref and $ref->[0] and $ref->[0] and (ref $ref->[0] eq 'ARRAY') or $self->error(FORGET_IT,"I forgot where I put it");
	
	$self->ok;
	
	$ref->[0]->[0].($ref->[0]->[1]?",$ref->[0]->[1]":"")
}
 
sub delete{
	my $self=shift;
	my($num,$pass,$uid)=@_;
	($num,my $subnum)=((split /,/,$num),0);
	my($ref);
	
	$ref=$self->query("select delpass,deleted,id from $self->{table} where num=? and subnum=?",$num,$subnum) or return;
	$self->error(FORGET_IT,"Post not found") unless $ref->[0];
	
	my($delpass,$deleted,$id)=@{ $ref->[0] };
	$self->error(FORGET_IT,"Post already deleted"),return if $deleted;
	
	if($uid ne $id){
		$self->error(FORGET_IT,"Wrong password"),return if $delpass ne $pass or not $delpass;
	}
	
	$self->query("update $self->{table} set deleted=1 where num=? and subnum=?",$num,$subnum);
	
	$self->ok;
}

sub database_delete{
	my $self=shift;
	my($num)=@_;
	($num,my $subnum)=((split /,/,$num),0);
	
	$self->query("delete from $self->{table} where num=? and subnum=?",$num,$subnum);
	if($subnum) {
		$self->query("delete from $self->{table}_local where parent = (select case when max(parent) = 0 then num else max(parent) end from $self->{table} where num=$num)");
		$self->query("replace into $self->{table}_local (num,parent,subnum,`timestamp`) 
			select num,case when parent = 0 then num else parent end,max(subnum),max(`timestamp`) from $self->{table}
				where num = (select max(num) from $self->{table} where parent=(select max(parent) from $self->{table} where num=$num))");
	}
}

sub insert{
	my $self=shift;
	my($thread)=@_;
	my $dbh=$self->{dbh};
	my($num,$parent,@posts);
	
	if(ref $thread eq 'HASH'){
		$parent=$thread->{parent};
		@posts=($thread);
	} elsif(ref $thread eq 'Board::Thread'){
		$num=$thread->{num};
		@posts=@{$thread->{posts}}
	} else{
		confess qq{Can only insert threads or hashes, not "}.(ref $thread).qq{"};
	}
	
	$num or $parent or $self->error(FORGET_IT,"Must specify a thread number for this board"),return 0;
	
	$self->query("replace $self->{table} values ".join ",",map{
		my $h=$_;
		
		my($location)=$num?
			# insert a post with specified number
			sprintf "%d,%d",$h->{num},($h->{subnum} or 0):
			
			# insert a post into thread, automatically get num and subnum
			sprintf "(select max(num) from (select * from $self->{table} where parent=%d or num=%d) as x),".
			"(select max(subnum)+1 from (select * from $self->{table} where num=(select max(num) from $self->{table} where parent=%d or num=%d)) as x)",
			$parent,$parent,$parent,$parent;
		
		sprintf "(%u,$location,%u,%u,%s,%d,%d,%s,%d,%d,%d,%s,%s,%d,%d,%s,%s,%s,%s,%s,%s,%s)",
			($h->{id} or 0),
			$h->{parent},
			$h->{date},
			$dbh->quote($h->{preview}),
			$h->{preview_w},
			$h->{preview_h},
			$dbh->quote($h->{media}),
			$h->{media_w},
			$h->{media_h},
			$h->{media_size},
			$dbh->quote($h->{media_hash}),
			$dbh->quote($h->{media_filename}),
			$h->{spoiler},
			$h->{deleted},
			$dbh->quote($h->{capcode} or 'N'),
			$dbh->quote($h->{email}),
			$dbh->quote($h->{name}),
			$dbh->quote($h->{trip}),
			$dbh->quote($h->{title}),
			$dbh->quote($h->{comment}),
			$dbh->quote($h->{password});
		
		}@posts
	) or return 0;

	# update board_local table if we're inserting a ghost post
	$self->query("replace into $self->{table}_local (num,parent,subnum,`timestamp`) 
		select num,case when parent = 0 then num else parent end as parent,max(subnum),max(`timestamp`) from $self->{table} 
			where num = (select max(num) from $self->{table} where parent=$parent)") if !$num;

	$self->ok;

	1;
}

sub query($$;@){
	my($self,$query)=(shift,shift);
	my $dbh=$self->{dbh};
	
	my $sth=$dbh->prepare($query) or ($self->error(FORGET_IT,$dbh->errstr),return 0);
	
	$sth->execute(@_) or ($self->error(FORGET_IT,$dbh->errstr),return 0);
	
	my $ref=($sth->fetchall_arrayref() or []);

	$sth->finish;
	
	$self->ok;
	
	$ref
}


















1;
