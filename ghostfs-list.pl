#!/usr/bin/perl
use strict;
use warnings;

use Fcntl ':mode';
use File::Find;
use Pod::Usage;

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

sub make_findfile {
	my ($root,$fdesc) = @_;

	chdir $root;
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
		print $fdesc ($path, "$stat[4]:$stat[5]", @times, $stat[7], $typechr, $target, $perms);
	}, '.');
}

my $dir = $ARGV[0];

pod2usage({ -message => 'Wrong argument count', -exitval => 2 }) if @ARGV != 1;
pod2usage({ -message => 'Not a directory', -exitval => 2 }) if ! -d $dir;

make_findfile($dir, \*STDOUT);

__END__

=head1 NAME

ghostfs-list - List generator for ghostfs

=head1 SYNOPSIS

B<ghostfs-list> I<directory>

=head1 DESCRIPTION

This script generates a file list for B<ghostfs>. It takes a directory as argument and outputs the list to stdout.

=head1 SEE ALSO

B<ghostfs>
