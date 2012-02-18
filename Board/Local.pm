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
	my $web_group=(delete $info{web_group} or "");
	my $self=$class->SUPER::new(@_);
	
	$path=~s!\\!/!g;
	$path=~s!/$!!g;
	
	$self->{path}="$path/$name";
	$self->{name}=$name;
	
	$self->{full}=(delete $info{full_pictures} or "");
	$self->{webgid} = getgrnam($web_group);

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
	("$path/thumb/$subdir/$sub2dir","$path/img/$subdir/$sub2dir");
}

sub make_dirs($;$){
	my $self=shift;
	my($num)=@_;
	my($path)=$self->{path};
	
	mkdir "$path";
	mkdir "$path/thumb";
	mkdir "$path/img" if $self->{full};
	
	my($subdir,$sub2dir)=$self->get_subdirs($num);
	if($subdir){
		mkdir "$path/thumb/$subdir";
		mkdir "$path/thumb/$subdir/$sub2dir";
		chmod 0775, "$path/thumb/$subdir", "$path/thumb/$subdir/$sub2dir";
		chown $<, $self->{webgid}, "$path/thumb/$subdir", "$path/thumb/$subdir/$sub2dir" if $self->{webgid};
		if($self->{full}){
			mkdir "$path/img/$subdir";
			mkdir "$path/img/$subdir/$sub2dir";
			chmod 0775, "$path/img/$subdir", "$path/img/$subdir/$sub2dir";
			chown $<, $self->{webgid}, "$path/img/$subdir", "$path/img/$subdir/$sub2dir" if $self->{webgid};
		}
	}
	
	("$path/thumb/$subdir/$sub2dir","$path/img/$subdir/$sub2dir");
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

sub get_media_location{
	my $self=shift;
	my($arg1,$arg2)=@_;
	
	for(ref $arg1){
		/^Board::Post/ and do{
			$arg2=$arg1->{media_filename};
			$arg1=($arg1->{parent} or $arg1->{num});
			last;
		};
		/^$/ and last;
		
		confess qq{Arguments can be either Board::Post, or two scalars};
	}
	
	my(undef,$dir)=$self->get_dirs($arg1);
	
	(0,"$dir/".($arg2 or ""))
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

	$self->ok;
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

	chmod 0664, "$thumb_dir/$h->{preview}";
	chown $<, $self->{webgid}, "$thumb_dir/$h->{preview}" if $self->{webgid};
	
	$self->ok;
	
	1;
}

sub delete_media_preview($) {
	my $self=shift;
	my ($num) = @_;

	my $h = $self->get_post($num);

	my($thumb_dir)=$self->get_dirs($h->{parent} or $h->{num});

	unlink "$thumb_dir/$h->{preview}" if $h->{preview} and $self->media_preview_exists($h);
}

sub insert_media{
	my $self=shift;
	my($h,$source)=@_;
	
	ref $h eq "Board::Post"
		or die "Can only insert Board::Post, tried to insert ".ref $h;
		
	my(undef,$media_dir)=$self->make_dirs($h->{parent} or $h->{num});
	
	return 0 unless $h->{media_filename};
	return 1 if -e "$media_dir/$h->{media_filename}";
	
	my($ref)=$source->get_media($h);
	return 2 if $source->error;
	
	open HANDLE,">$media_dir/$h->{media_filename}"
		or die "$! - $media_dir/$h->{media_filename}";
	binmode HANDLE;
	print HANDLE $$ref;
	close HANDLE;

	chmod 0664, "$media_dir/$h->{preview}";
	#chown $<, 80, "$media_dir/$h->{preview}";

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
