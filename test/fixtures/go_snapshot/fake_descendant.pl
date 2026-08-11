#!/usr/bin/perl

use strict;
use warnings;

my $mode = $ENV{GO_SNAPSHOT_TEST_MODE} // die "missing mode\n";
my $log_path = $ENV{GO_SNAPSHOT_TEST_LOG} // die "missing log\n";

sub record_event {
  my ($event, $detail) = @_;
  open my $log, '>>', $log_path or die "open log: $!\n";
  print {$log} join('|', $event, $$, getpgrp(), $detail // ''), "\n";
  close $log or die "close log: $!\n";
}

record_event('descendant-started', $mode);
record_event(
  'descendant-fixed-fds',
  'fd8=' . (-e '/dev/fd/8' ? 'open' : 'closed') .
    ',fd9=' . (-e '/dev/fd/9' ? 'open' : 'closed'),
);

if ($mode eq 'signal') {
  $SIG{INT} = sub {
    record_event('descendant-int', 'INT');
    exit 0;
  };
  $SIG{TERM} = sub {
    record_event('descendant-term', 'TERM');
    exit 0;
  };
} elsif ($mode eq 'stubborn' ||
         $mode eq 'stubborn-visible-term' ||
         $mode eq 'delayed127' ||
         $mode eq 'delayed138' ||
         $mode eq 'race-late127') {
  $SIG{INT} = sub { record_event('descendant-int-ignored', 'INT'); };
  $SIG{TERM} = sub { record_event('descendant-term-ignored', 'TERM'); };
} else {
  exit 65;
}

while (1) {
  sleep 1;
}
