package Lim::Plugin::Orr::Server::NodeWatcher;

use common::sense;

use Scalar::Util qw(weaken);
use AnyEvent ();

use Lim::Plugin::Orr ();

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server::NodeWatcher - Node watcher functions for the server
class of the OpenDNSSEC Redundancy Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;

our $NODE_WATCHER_TIMER = 30;

=head1 SYNOPSIS

  use base qw(Lim::Plugin::Orr::Server::NodeWatcher);

=head1 METHODS

These methods handles the nodes for OpenDNSSEC Redundancy Robot.

=over 4

=item NodeWatcherTimer

=cut

sub NodeWatcherTimer {
    my ($self, $after) = @_;
    my $real_self = $self;
    weaken($self);

    $self->{node_watcher}->{timer} = AnyEvent->timer(
        after => defined $after ? $after : $NODE_WATCHER_TIMER,
        cb => sub {
            defined $self and $self->NodeWatcherRun;
        });
}

=item NodeWatcherStop

=cut

sub NodeWatcherStop {
    my ($self) = @_;

    $self->{logger}->debug('NodeWatcherStop()');
    
    delete $self->{node_watcher}->{timer};
}

=item NodeWatcherRun

=cut

sub NodeWatcherRun {
    my ($self) = @_;
    
    $self->{logger}->debug('NodeWatcherRun() start');

    unless ($self->_isReady) {
        $self->NodeWatcherTimer;
        return;
    }
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

1; # End of Lim::Plugin::Orr::Server::NodeWatcher
