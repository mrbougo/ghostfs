#!/usr/bin/perl
use strict;
use warnings;
use Fcntl ':mode';
use File::Find;
use Data::Dumper;

#Time::HiRes does not provide lstat, use inline C code instead
use Inline C => <<'EOC';

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

void lstat_nsec(char* fname)
{
    struct stat st;
	Inline_Stack_Vars;
	Inline_Stack_Reset;

    if (-1 == lstat(fname, &st)) {
		Inline_Stack_Push(&PL_sv_undef);
		Inline_Stack_Done;
        return;
	}

	Inline_Stack_Push(sv_2mortal(newSViv((long)st.st_atim.tv_nsec)));
	Inline_Stack_Push(sv_2mortal(newSViv((long)st.st_mtim.tv_nsec)));
	Inline_Stack_Push(sv_2mortal(newSViv((long)st.st_ctim.tv_nsec)));
	Inline_Stack_Done;
}
EOC

my %types_itos = (
	(S_IFREG) => 'f',
	(S_IFDIR) => 'd',
	(S_IFLNK) => 'l',
);

my %types_stoi = (
	'f' => S_IFREG,
	'd' => S_IFDIR,
	'l' => S_IFLNK,
);

sub make_findfile {
	my ($fname,$root) = @_;

	open(my $f, ">", $fname) or die $!;

	find( sub{
		my $path = $File::Find::name;
		my @stat = lstat $_;

		my $mode = $stat[2];
		my $typechr = $types_itos{$mode & S_IFMT} or die "unsupported filemode $mode";
		my $perms = sprintf('%04o', $mode & 07777);
		my $target = $typechr eq 'l' ? readlink $path : '';

		my @stimes = @stat[8,9,10];
		my @ntimes = lstat_nsec($_);
		my @times = map "$stimes[$_].$ntimes[$_]", 0 .. 2;
		
		local $, = "\000";
		local $\ = "\000\n";
		print $f ($path, "$stat[4]:$stat[5]", @times, $stat[7], $typechr, $target, $perms);
	}, $root);

	close $f;
}

#prepare tree structure from find-file
#(see SNAP on perlmonks)
sub prepare_tree {
	my ($fname) = @_;

	open(my $f, "<", $fname) or die $!;

	my %tree;
	my @s; #stack, associates full directory paths with their parent node
	my $tree = my $node = { children => [] };
	while($_ = next_record($f)) {
		my %entry;
		my $path;
		($path, @entry{qw(usergroup atime mtime ctime size type linktarget perm)})
			= split "\000";
		delete $entry{linktarget} if $entry{linktarget} eq '';

		my ($parent,$name) = $path =~ m|(.*)\/(.*)|;
		$entry{name} = $name;

		$node = (pop @s)->[1] while @s and $parent ne $s[-1][0];
		push @$node{children}, my $child = \%entry;

		next unless $entry{type} eq 'd';

		push @s, [ $path, $node ];

		$node = $child;
		$node->{children} = [];
	}

	close $f;

	$tree = $tree->{children}[0];
	return $tree;
}

#get next record. Format: nine fields separated by eight nulls,
# followed by one null and a newline
sub next_record {
	my ($f) = @_;

	local $/ = "\000";

	return undef if eof($f);

	my $out = '';
	$out = $out . readline($f) for 1 .. 9;

	#last newline:
	read $f, $_, 1 or die;

	return $out;
}

#print Dumper prepare_tree($ARGV[0]);
make_findfile(@ARGV);

