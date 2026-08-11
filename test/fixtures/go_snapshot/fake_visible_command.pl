#!/usr/bin/perl

use strict;
use warnings;

my $log_path = $ENV{GO_SNAPSHOT_TEST_LOG} // die "missing log\n";
my $descendant = $ENV{GO_SNAPSHOT_DESCENDANT_FIXTURE} // die "missing descendant\n";

sub record_event {
  my ($event, $detail) = @_;
  open my $log, '>>', $log_path or die "open log: $!\n";
  print {$log} join('|', $event, $$, getpgrp(), $detail // ''), "\n";
  close $log or die "close log: $!\n";
}

$| = 1;
select STDERR;
$| = 1;
select STDOUT;

print STDOUT "fixture visible stdout\n";
print STDERR "fixture visible stderr\n";
record_event(
  'visible-fixed-fds',
  'fd8=' . (-e '/dev/fd/8' ? 'open' : 'closed') .
    ',fd9=' . (-e '/dev/fd/9' ? 'open' : 'closed'),
);

my $child = fork();
die "fork: $!\n" unless defined $child;
if ($child == 0) {
  exec '/usr/bin/perl', $descendant;
  die "exec descendant: $!\n";
}
record_event('descendant-recorded', $child);

$SIG{INT} = sub {
  record_event('command-int-visible', 'INT');
  print STDERR "fixture INT handler stderr\n";
};
$SIG{TERM} = sub {
  record_event('command-term-visible', 'TERM');
  print STDERR "fixture TERM handler stderr\n";
};

while (1) {
  sleep 1;
}
