package Lim::Plugin::Orr::Server::NodeWatcher;

use common::sense;

use Carp;
use Scalar::Util qw(weaken blessed);
use AnyEvent ();
use Log::Log4perl ();

use Lim::Plugin::Orr ();
use Lim::Plugin::Orr::Server::Node ();

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server::NodeWatcher - Node Watcher for the OpenDNSSEC
Redundancy Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;

our $NODE_WATCHER_TIMER = 30;

=head1 SYNOPSIS

  use base qw(Lim::Plugin::Orr::Server::NodeWatcher);

=head1 DESCRIPTION

This is a Node Watcher for the OpenDNSSEC Redundancy Robot that will handle node
actions such as syncing information between nodes.

=head1 METHODS

These methods handles the nodes for OpenDNSSEC Redundancy Robot.

=over 4

=item $db = Lim::Plugin::Orr::Server::NodeWatcher->new(key => value...);

Create a new Node Watcher object for the OpenDNSSEC Redundancy Robot.

=over 4

=item server

=back

=cut

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my %args = ( @_ );
    my $self = {
        logger => Log::Log4perl->get_logger,
        node => {}
    };
    bless $self, $class;

    Lim::OBJ_DEBUG and $self->{logger}->debug('new ', __PACKAGE__, ' ', $self);
    $self;
}

sub DESTROY {
    my ($self) = @_;
    Lim::OBJ_DEBUG and $self->{logger}->debug('destroy ', __PACKAGE__, ' ', $self);
    
    $self->Stop;
}

=item Timer

=cut

sub Timer {
    my ($self, $after) = @_;
    my $real_self = $self;
    weaken($self);

    $self->{timer} = AnyEvent->timer(
        after => defined $after ? $after : $NODE_WATCHER_TIMER,
        cb => sub {
            defined $self and $self->Run;
        });
}

=item Stop

=cut

sub Stop {
    my ($self) = @_;

    $self->{logger}->debug('Stop()');
    
    delete $self->{timer};
}

=item Run

=cut

sub Run {
    my ($self) = @_;
    
    $self->{logger}->debug('Run() start');
    $self->{logger}->debug('Run() done');

    $self->Timer;
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
