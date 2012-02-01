#!/usr/bin/perl
use strict;
use warnings;
use Fcntl ':mode';
use Fuse;

use POSIX qw(EINVAL ENOENT);

use Data::Dumper;

my $tree;

my %types_stoi = (
	'f' => S_IFREG,
	'd' => S_IFDIR,
	'l' => S_IFLNK,
);

#prepare tree structure from find-file
#(see SNAP on perlmonks)
sub prepare_tree {
	my ($fname) = @_;

	open(my $f, "<", $fname) or die $!;

	my %tree;
	my @s; #stack, associates full directory paths with their parent node
	my $tree = my $node = {};
	while($_ = next_record($f)) {
		m/	^.*?      \000   #path
			 \d+:\d+  \000   #uid:gid
			 \d+\.\d+ \000   #atime
			 \d+\.\d+ \000   #mtime
			 \d+\.\d+ \000   #ctime
			 \d+      \000   #size
			 [dlf]    \000   #type
			 .*?      \000   #link target
			 [0-7]{4} \000$ #permissions
			/sx or die "bad record: $_";

		my %entry;
		my $path;
		($path, @entry{qw(usergroup atime mtime ctime size type linktarget perm)})
			= split "\000";
		delete $entry{linktarget} if $entry{linktarget} eq '';

		my ($parent,$name) = $path =~ m|(?:(.*)/)?(.*)|;
		$entry{name} = $name;

		$node = (pop @s)->[1] while @s and $parent ne $s[-1][0];
		$node->{children}{$name} = my $child = \%entry;

		next unless $entry{type} eq 'd';

		push @s, [ $path, $node ];

		$node = $child;
	}

	close $f;

	$tree = (values $tree->{children})[0];
	return $tree;
}

#get next record. Format: nine fields separated by eight nulls,
# followed by one null and a newline
sub next_record {
	my ($f) = @_;

	local $/ = "\000";

	return undef if eof($f);

	my $out = '';
	for (1 .. 9) {
		die 'unexpected eof' if eof($f);
		$out = $out . readline($f);
	}

	#last newline:
	read $f, $_, 1 or die;

	return $out;
}


sub getfile {
	my @path = split '/', shift;
	shift @path; # $_[0] starts with /

	my $node = $tree;
	foreach (@path) {
		$node = $node->{children}{$_} or return undef;
	}
	return $node;
}

sub getattr {
	my $file = getfile(shift) or return -ENOENT();

	my $dev = 0;
	my $ino = 1;
	my $mode = $types_stoi{$file->{type}} | oct $file->{perm};
	my $nlink = 1;
	my ($uid,$gid) = split ':', $file->{usergroup};
	my $rdev = 0;
	my $size = $file->{size};
	my $atime = int $file->{atime};
	my $mtime = int $file->{mtime};
	my $ctime = int $file->{ctime};
	my $blksize = 512;
	my $blocks = 1;

	return ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime,
	        $ctime, $blksize, $blocks);
}

sub readlink {
	my $file = getfile(shift) or return -ENOENT();

	return -EINVAL() if $file->{type} ne 'l';
	return $file->{linktarget};
}

sub getdir {
	my $file = getfile(shift) or return -ENOENT();

	return -EINVAL() if $file->{type} ne 'd';
	return ('.', '..', keys %{$file->{children}});
}

my ($mountpoint, $listfname) = @ARGV;
$tree = prepare_tree($listfname);

Fuse::main(
	debug => 1,
	mountpoint => $mountpoint,
	getattr => \&getattr,
	readlink => \&readlink,
	getdir => \&getdir,
);
