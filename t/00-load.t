#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Lim::Plugin::Orr' ) || print "Bail out!\n";
}

diag( "Testing Lim::Plugin::Orr $Lim::Plugin::Orr::VERSION, Perl $], $^X" );
