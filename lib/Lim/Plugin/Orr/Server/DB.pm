package Lim::Plugin::Orr::Server::DB;

use common::sense;

use Carp;
use Scalar::Util qw(weaken blessed);
use UUID ();

use Lim::Plugin::Orr ();

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server::DB - Database functions for the server class of the
OpenDNSSEC Redundancy Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;

=head1 SYNOPSIS

  use base qw(Lim::Plugin::Orr::Server::DB);

=head1 METHODS

These methods handles the database for OpenDNSSEC Redundancy Robot.

=over 4

=item dbSetup

Setup the database, create all the tables if they dont exist or upgrade an
existing database if there is a new version.

=cut

sub dbSetup {
    my ($self, $dbh, $cb) = @_;
    
    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    unless (blessed $dbh and $dbh->isa('AnyEvent::DBI')) {
        $@ = '$dbh is not AnyEvent::DBI';
        $cb->();
        return;
    }
    
    $cb->(1);
}

=back

=head1 AUTHOR

Jerry Lundström, C<< <lundstrom.jerry at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to L<https://github.com/jelu/lim-plugin-orr/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lim::Plugin::Orr

You can also look for information at:

=over 4

=item * Lim issue tracker (report bugs here)

L<https://github.com/jelu/lim-plugin-orr/issues>

=back

=head1 ACKNOWLEDGEMENTS

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Jerry Lundström.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Lim::Plugin::Orr::Server::DB
