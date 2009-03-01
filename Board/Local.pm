package Board::Local;

use strict;
use warnings;
use Carp qw/confess/;

use Board;
our @ISA=qw/Board/;

use File::Path;

sub new($$;%){
	my $class=shift;
	my $name=shift;
	my(%info)=(@_);
	
	my $path=(delete $info{images}	or die);
	my $self=$class->SUPER::new(@_);
	
	$path=~s!\\!/!g;
	$path=~s!/$!!g;
	
	$self->{path}="$path/$name";
	$self->{name}=$name;
	
	mkdir $path;
	mkdir $self->{path};

	bless $self,$class;
}

sub magnitude($$){
	my $self=shift;
	
	$self->SUPER::magnitude($_[0]);
}

sub get_subdirs($$){
	my $self=shift;
	my($num)=@_;
	
	my($subdir,$sub2dir)=$num=~/(\d+?)(\d{2})\d{0,3}$/;
	(sprintf "%04d",$subdir),(sprintf "%02d",$sub2dir);
}

sub get_dirs($$){
	my $self=shift;
	my($num)=@_;
	my($path)=$self->{path};

	my($subdir,$sub2dir)=$self->get_subdirs($num);
	("$path/thumb/$subdir/$sub2dir");
}

sub make_dirs($;$){
	my $self=shift;
	my($num)=@_;
	my($path)=$self->{path};
	
	mkdir "$path";
	mkdir "$path/thumb";
	
	my($subdir,$sub2dir)=$self->get_subdirs($num);
	if($subdir){
		mkdir "$path/thumb/$subdir";
		mkdir "$path/thumb/$subdir/$sub2dir";
	}
	
	("$path/thumb/$subdir/$sub2dir");
}

sub get_media_preview($$){
	my $self=shift;
	
	my($err,$filename)=$self->get_media_preview_location(@_);
	$err and return $err;
	
	open HANDLE,"$filename" or return "$! - $filename";
	binmode HANDLE;
	local $/;
	my $content=<HANDLE>;
	close HANDLE;
	
	\$content;
}

sub get_media_preview_location{
	my $self=shift;
	my($arg1,$arg2)=@_;
	
	for(ref $arg1){
		/^Board::Post/ and do{
			$arg2=$arg1->{preview};
			$arg1=($arg1->{parent} or $arg1->{num});
			last;
		};
		/^$/ and last;
		
		confess qq{Arguments can be either Board::Post, or two scalars};
	}
	
	my($dir)=$self->get_dirs($arg1);
	
	(0,"$dir/".($arg2 or ""))
}

sub insert($$){
	my $self=shift;

	$self->error(0);
}

sub insert_media_preview{
	my $self=shift;
	my($h,$source)=@_;
	
	ref $h eq "Board::Post"
		or die "Can only insert Board::Post, tried to insert ".ref $h;
		
	my($thumb_dir)=$self->make_dirs($h->{parent} or $h->{num});
	
	return 0 unless $h->{preview};
	return 1 if -e "$thumb_dir/$h->{preview}";
	
	my($ref)=$source->get_media_preview($h);
	return 2 if $source->error;
	
	open HANDLE,">$thumb_dir/$h->{preview}"
		or die "$! - $thumb_dir/$h->{preview}";
	binmode HANDLE;
	print HANDLE $$ref;
	close HANDLE;
	
	$self->ok;
	
	1;
}

sub media_preview_exists{
	my $self=shift;
	my($h,$source)=@_;
	
	ref $h eq "Board::Post"
		or die "Can work with Board::Post, received ".ref $h;
	
	my($thumb_dir)=$self->make_dirs($h->{parent} or $h->{num});

	return 1 if -e "$thumb_dir/$h->{preview}";
	
	0;	
}