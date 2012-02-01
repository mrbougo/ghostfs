#!/usr/bin/perl
use strict;
use warnings;
use Fcntl ':mode';


use Data::Dumper;

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

