package Board::Sphinx_Mysql;

use strict;
use warnings;
use Carp qw/confess cluck/;
use DBI;

use Date::Parse;

use Board::Local;
use Board::Errors;
use Board::Mysql;
our @ISA = qw/Board::Mysql/;

sub new($$;%){
    my $class=shift;
    my $path=shift;
    my(%info)=(@_);
    
    my $sx_host     =(delete $info{sx_host}     or "127.0.0.1");
    my $sx_port     =(delete $info{sx_port}     or 9306);

    my $self=$class->SUPER::new($path,%info);
    
    $self->{sx_host}            = $sx_host;
    $self->{sx_port}            = $sx_port;


    bless $self,$class;
}


sub _connect_sphinx {
    my $self=shift;
    
    return DBI->connect(
        "DBI:mysql:database=sphinx;host=$self->{sx_host}:$self->{sx_port}",
        '',
        '',
        {AutoCommit=>1,PrintError=>0,mysql_enable_utf8=>1},
    )
}

sub search($$$$){
    my $self=shift;
    my($text,$limit,$offset,%settings)=@_;
    my $dbh=$self->{dbh};

    $limit=int $limit;
    $offset=defined $offset ? int $offset : 0;

    my @matches;
    my @conditions;
    my @sql_conditions;
    my @index_hint;

    push @matches,'@title '.$self->_sphinx_escape($settings{subject}).' '
        if $settings{subject};

    push @matches,'@name '.$self->_sphinx_full_escape($settings{name}).' '
        if $settings{name};

    push @matches,'@trip '.$self->_sphinx_full_escape($settings{tripcode}).' '
        if $settings{tripcode};

    push @matches,'@media '.$self->_sphinx_full_escape($settings{filename}).' '
        if $settings{filename};

    push @matches,'@email '.$self->_sphinx_full_escape($settings{email}).' '
        if $settings{email};

    push @matches,'@comment '.$self->_sphinx_escape($text).' '
        if $text;
    
    push @conditions,"timestamp > " . str2time($settings{datefrom}) and
    push @sql_conditions,"timestamp > " . str2time($settings{datefrom})
        if str2time($settings{datefrom});

    push @conditions,"timestamp < " . str2time($settings{dateto}) and
    push @sql_conditions,"timestamp < " . str2time($settings{dateto})
        if str2time($settings{dateto});

    push @sql_conditions,"media_hash=".$dbh->quote($settings{media_hash}) and
    push @index_hint,"media_hash_index"
       if $settings{media_hash};

    push @conditions,"is_op=1" and
    push @sql_conditions,"parent=0"
        if $settings{op};

    push @conditions,"is_deleted=1" and
    push @sql_conditions,"deleted=1"
        if $settings{showdel} and not $settings{shownodel};

    push @conditions,"is_deleted=0" and
    push @sql_conditions,"deleted=0"
        if $settings{shownodel} and not $settings{showdel};

    push @conditions,"is_internal=1" and
    push @sql_conditions,"subnum!=0"
        if $settings{showint} and not $settings{showext};

    push @conditions,"is_internal=0" and
    push @sql_conditions,"subnum=0"
        if $settings{showext} and not $settings{showint};

    my $cap = substr(ucfirst($settings{cap}), 1);
    push @conditions,"cap=78" and
    push @sql_conditions,"capcode=".$dbh->quote($cap)
    	if $settings{cap} eq 'user';
	push @conditions,"cap=77" and
    push @sql_conditions,"capcode=".$dbh->quote($cap)
		if $settings{cap} eq 'mod';
	push @conditions,"cap=65" and
    push @sql_conditions,"capcode=".$dbh->quote($cap)
		if $settings{cap} eq 'admin';
	push @conditions,"cap=68" and
    push @sql_conditions,"capcode=".$dbh->quote($cap)
		if $settings{cap} eq 'dev';

    my $ord=$settings{ord};
    my $query_ord="timestamp desc";

    $query_ord="timestamp asc" if $ord and $ord eq 'old';

    my $res = $settings{res};
    my $op = 0;
    $op = 1 if $res and $res eq 'op';

    my $condition=join "",map{" and $_"}@conditions;
    my $match=$dbh->quote(join "",@matches);

    my $sql_condition=join "",map{"$_ and "}@sql_conditions;
    my $index_hint=@index_hint?
        "use index(".(join ",",@index_hint).")":
        "";
        
    my $query;
    if($match eq "''" and !$op) {
        $query = "select * from $self->{table} $index_hint where $sql_condition 1 order by $query_ord limit $offset, $limit";
    } else {
        my $sel_id = "id";
        my $query_grp = "";
        if($op) {
            $sel_id = "tnum"; 
            $query_grp = "group by tnum";
        }
        
        my $squery="select $sel_id from $self->{table}_ancient, $self->{table}_main, $self->{table}_delta
                        where match($match) $condition $query_grp order by $query_ord limit $offset, $limit option max_matches=5000;";
        my($sref)=($self->query_sphinx($squery) or return);
        return if !@$sref;

        if(!$op) {
            $query = "select * from $self->{table} where doc_id in (". join(",",map{@$_[0]} @$sref) . ") order by $query_ord;";
        } else {
            $query = "select * from $self->{table} where num in (". join(",",map{@$_[0]} @$sref) . ") and subnum = 0 order by $query_ord;";
        }
    }

    my($ref)=($self->query($query) or return);

    map{$self->_read_post($_)} @$ref
}

sub _sphinx_full_escape($) {
    my ($self, $query)=(shift,shift);
    $query=~ s/([=\(\)|\-!@~"&\/\\\^\$\=])/\\$1/g;
    return $query;
}

sub _sphinx_escape($) {
    my ($self, $query)=(shift,shift);
    $query=~ s/([=\(\)\!@~&\/\\\^\$\=])/\\$1/g;
    $query=~ s/\"([^\s]+)-([^\s]*)\"/$1-$2/g;
    $query=~ s/([^\s]+)-([^\s]*)/"$1\\-$2"/g;
    return $query;
}

sub _log_bad_query($) {
    my ($self,$query) = (shift,shift);
    open HANDLE,">>bad_queries.txt";
    print HANDLE "Bad query: $query\n";
    close HANDLE;
}

sub query_sphinx($$;@){
    my($self,$query)=(shift,shift);
    my $dbh_sphinx = $self->_connect_sphinx or ($self->error(FORGET_IT,"Search backend seems to be offline. Contact website admin?"),return 0);;

    unless($dbh_sphinx and $dbh_sphinx->ping) {
        $dbh_sphinx = $self->_connect_sphinx or ($self->error(FORGET_IT,"Lost connection, cannot reconnect to search backend."),return 0);
    }

    my $sth=$dbh_sphinx->prepare($query) or return [];

    $sth->execute(@_) or ($self->error(FORGET_IT,"I can't figure your search query out! Try reading the search FAQ. Report a new bug or send an email if you think your query should have worked."),return 0);

    my $ref=($sth->fetchall_arrayref() or []);
    $sth->finish;
    $self->ok;
    $dbh_sphinx->disconnect();

    $ref
}





1;
