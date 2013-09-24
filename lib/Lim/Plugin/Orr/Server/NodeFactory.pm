package Lim::Plugin::Orr::Server::NodeFactory;

use common::sense;

use Carp;
use Scalar::Util qw(weaken);

use Lim::Plugin::Orr ();
use Lim::Plugin::Orr::Server::Node ();

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server::NodeFactory - Node Factory functions for the
OpenDNSSEC Redundancy Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;

our %NODES;

=head1 SYNOPSIS

  use Lim::Plugin::Orr::Server::NodeFactory;
  
  my $node = Lim::Plugin::Orr::Server::NodeFactory->new(...);

=head1 DESCRIPTION

This is a factory class for Node, it will make a instance of Node based on the
URI parameter.

=head1 METHODS

=over 4

=item $node = Lim::Plugin::Orr::Server::NodeFactory->new(...);

Creates a new Node object or returns a strong reference to an already existing
Node object at the same URI.

=cut

sub new {
    my $this = shift;
    my %args = ( @_ );

    unless (defined $args{uri}) {
        confess __PACKAGE__, ': Missing uri';
    }
    
    if (exists $NODES{$args{uri}}) {
        my $node = $NODES{$args{uri}};
        if (defined $node) {
            return $node;
        }
    }

    my $node = Lim::Plugin::Orr::Server::Node->new(%args);
    $NODES{$args{uri}} = $node;
    weaken($NODES{$args{uri}});
    
    $node;
}

=back

=head1 AUTHOR

Jerry Lundström, C<< <lundstrom.jerry at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to L<https://github.com/jelu/lim-plugin-orr/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lim::Plugin::Orr::Server::NodeFactory

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

1; # End of Lim::Plugin::Orr::Server::NodeFactory
