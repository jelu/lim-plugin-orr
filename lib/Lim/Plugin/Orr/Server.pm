package Lim::Plugin::Orr::Server;

use common::sense;

use Fcntl qw(:seek);
use IO::File ();
use Digest::SHA ();
use Scalar::Util qw(weaken);

use Lim::Plugin::Orr ();

use Lim::Util ();

use base qw(Lim::Component::Server);

=encoding utf8

=head1 NAME

...

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;

=head1 SYNOPSIS

...

=head1 SUBROUTINES/METHODS

=head2 Init

=cut

sub Init {
    my $self = shift;
    my %args = ( @_ );
}

=head2 Destroy

=cut

sub Destroy {
}

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

Copyright 2012-2013 Jerry Lundström.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Lim::Plugin::Orr::Server
