package Board::Mysql;

use strict;
use warnings;
use Carp qw/confess cluck/;
use DBI;

use Date::Parse;

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
	
	$self->{db_name}			= $database;
	$self->{db_host}			= $host;
	$self->{db_connstr} 		= $connstr;
	$self->{db_username} 		= $name;
	$self->{db_password} 		= $password;

    my $dbh = $self->_connect or die $DBI::errstr;

	$self->{dbh}				= $dbh;
	$self->{table}				= $table;
	$self->{spam_table}			= "${table}_spam";
	$self->{threads_per_page}	= 20;
	$self->{opts}				= $opts;
	
	$self->_create_table if $create_new;

	bless $self,$class;
}

sub _connect {
	my $self=shift;

	return DBI->connect(
        ($self->{db_connstr} or "DBI:mysql:database=$self->{db_name};host=$self->{db_host}"),
        $self->{db_username},
        $self->{db_password},
        {AutoCommit=>1,PrintError=>0,mysql_enable_utf8=>1},
    )
}

sub _create_table($){
	my $self=shift;

	$self->{dbh}->do(<<HERE);
create table if not exists $self->{table} (
	doc_id int unsigned not null auto_increment,
	id decimal(39,0) unsigned not null default '0',
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
	media_size int unsigned,
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
	
	primary key (doc_id),
	
	unique num_subnum_index (num, subnum),
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
}

sub _read_post($$){
	my $self=shift;
	my($doc_id,$id,$num,$subnum,$parent,$date,$preview,$preview_w,$preview_h,
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
select * from $self->{table} where num=? union select * from $self->{table} where parent=? order by num,subnum asc
HERE
}

sub get_thread_range($$$){
    my $self=shift;
    my($thread,$limit)=@_;

$self->_read_thread($self->query(<<HERE,$thread,$thread,$limit) or return);
select * from
   (select * from $self->{table} where num=? union 
       select * from $self->{table} where parent=? order by num desc,subnum desc limit ?) as tbl 
order by tbl.num asc,subnum asc
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
    (select unq_parent, max_timestamp from
        (select parent as unq_parent, max(b.timestamp) as max_timestamp, b.num from
            (select num, parent, subnum, timestamp, email from $self->{table}
                where subnum > 0 and (email <> 'sage' or email is null or (email = 'sage' and parent = 0))
                order by timestamp desc limit 0, 100000) as b
            group by unq_parent order by max(b.timestamp) desc limit ? offset ?) as t
    left join $self->{table} as g on g.num = t.unq_parent and g.subnum = 0) as j
where $self->{table}.parent = j.unq_parent or $self->{table}.num = j.unq_parent
order by j.max_timestamp desc, num, subnum asc;
HERE
select $self->{table}.* from
	(select num from $self->{table} where parent=0 order by num desc limit ? offset ?) as threads join $self->{table}
		on threads.num=$self->{table}.num or threads.num=$self->{table}.parent
			order by case parent when 0 then $self->{table}.num else parent end desc,num,subnum asc
THERE
	for my $ref(@results){
		my($doc_id,$id,$num,$subnum,$parent)=@$ref;
		
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
	$offset=defined $offset ? int $offset : 0;
	
	my @conditions;
	my @index_hint;
	
	push @conditions,"name=".$dbh->quote($settings{name}) and
	push @index_hint,"name_index"
		if $settings{name};
	
	push @conditions,"trip=".$dbh->quote($settings{tripcode}) and
	push @index_hint,"trip_index"
		if $settings{tripcode};

	push @conditions,"timestamp > " . str2time($settings{datefrom})
		if str2time($settings{datefrom});

	push @conditions,"timestamp < " . str2time($settings{dateto})
		if str2time($settings{dateto});
	
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
}

sub insert{
	# That sprintf below spouts a billion of uninitialized value warnings
	# really needs to be fixed, my error logs can't take it easy like this
	no warnings;

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
	my $sage = 0;

	$self->query("insert into $self->{table} values ".join(",",map{
		my $h=$_;
		$sage = 1 if $h->{email} eq 'sage' and $self->{sage};
		
		my($location)=$num?
			# insert a post with specified number
			sprintf "%d,%d",$h->{num},($h->{subnum} or 0):
			
			# insert a post into thread, automatically get num and subnum
			sprintf "(select max(num) from (select * from $self->{table} where parent=%d or num=%d) as x),".
			"(select max(subnum)+1 from (select * from $self->{table} where num=(select max(num) from $self->{table} where parent=%d or num=%d)) as x)",
			$parent,$parent,$parent,$parent;
		
		sprintf "(NULL, %s,$location,%u,%u,%s,%d,%d,%s,%d,%d,%d,%s,%s,%d,%d,%s,%s,%s,%s,%s,%s,%s)",
			defined $h->{id} ? $h->{id}->bstr() : 0,
			$h->{parent},
			$h->{date},
			$h->{preview} ? $dbh->quote($h->{preview}) : 'NULL',
			$h->{preview_w},
			$h->{preview_h},
			$h->{media} ? $dbh->quote($h->{media}) : 'NULL',
			$h->{media_w},
			$h->{media_h},
			$h->{media_size},
			$h->{media_hash} ? $dbh->quote($h->{media_hash}) : 'NULL',
			$h->{media_filename} ? $dbh->quote($h->{media_filename}) : 'NULL',
			$h->{spoiler},
			$h->{deleted},
			$h->{capcode} ? $dbh->quote($h->{capcode}) : "'N'",
			$h->{email} ? $dbh->quote($h->{email}) : 'NULL',
			$h->{name} ? $dbh->quote($h->{name}) : 'NULL',
			$h->{trip} ? $dbh->quote($h->{trip}) : 'NULL',
			$h->{title} ? $dbh->quote($h->{title}) : 'NULL',
			$h->{comment} ? $dbh->quote($h->{comment}) : 'NULL',
			$h->{password} ? $dbh->quote($h->{password}) : 'NULL';
		
		}@posts) . " on duplicate key update comment = values(comment), deleted = values(deleted), media = coalesce(values(media), media)"
	) or return 0;

	$self->ok;

	1;
}

sub query($$;@){
	my($self,$query)=(shift,shift);
 	unless($self->{dbh} and $self->{dbh}->ping) {
		$self->{dbh} = $self->_connect or ($self->error(FORGET_IT,"Lost connection, cannot reconnect to database."),return 0);
	}

	my $dbh=$self->{dbh};

	my $sth=$dbh->prepare($query) or ($self->error(FORGET_IT,$dbh->errstr),return 0);
	
	$sth->execute(@_) or ($self->error(FORGET_IT,$dbh->errstr),return 0);
	
	my $ref=($sth->fetchall_arrayref() or []);

	$sth->finish;
	
	$self->ok;
	
	$ref
}


















1;
