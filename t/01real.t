#!/usr/bin/perl

use Apache::test qw(skip_test have_httpd test);
skip_test unless have_httpd;

use strict;
use vars qw($TEST_NUM);

my %requests = (
   # mod_perl test module: should succeed with session cookie tracking
	1  => { 
	        uri     => '/session',
	        method  => 'GET',
	       },
   # mod_perl test module: should succeed with session URI tracking
	2  => { 
	        uri     => '/uri-session',
	        method  => 'GET',
	       },
   # mod_perl test module: should succeed with cookie session tracking
	3  => { 
	        uri     => '/session-bh',
	        method  => 'GET',
	       },
   # mod_perl test module: should succeed without session tracking
	4  => { 
	        uri     => '/no-session',
	        method  => 'GET',
	       },
);

print "1.." . (keys %requests) . "\n";

test ++$TEST_NUM, 1;
test ++$TEST_NUM, 1;
test ++$TEST_NUM, 1;
test ++$TEST_NUM, 1;

foreach my $testnum (sort {$a <=> $b} keys %requests) {
	my $response = Apache::test->fetch($requests{$testnum});
	my $content = $response->content;
	print "$content\n" if $ENV{TEST_VERBOSE};
}

