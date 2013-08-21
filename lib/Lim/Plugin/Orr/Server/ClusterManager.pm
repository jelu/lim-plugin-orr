package Lim::Plugin::Orr::Server::ClusterManager;

use common::sense;

use Carp;
use Scalar::Util qw(weaken blessed);
use AnyEvent ();
use Log::Log4perl ();

use Lim::Plugin::Orr ();
use Lim::Plugin::Orr::Server::ZoneInput ();

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server::ClusterManager - Cluster Manager for the OpenDNSSEC
Redundancy Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;

our $TIMER_INTERVAL = 5;

=head1 SYNOPSIS

  use Lim::Plugin::Orr::Server::ClusterManager;
  
  my $cluster_manager = Lim::Plugin::Orr::Server::ClusterManager->new(...);

=head1 DESCRIPTION

This is a Cluster Manager for the OpenDNSSEC Redundancy Robot that will ...

=head1 METHODS

These methods handles the clusters for OpenDNSSEC Redundancy Robot.

=over 4

=item $cluster_manager = Lim::Plugin::Orr::Server::ClusterManager->new(...);

Create a new Cluster Manager object for the OpenDNSSEC Redundancy Robot.

=cut

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my %args = ( @_ );
    my $self = {
        logger => Log::Log4perl->get_logger
    };
    bless $self, $class;

    unless (blessed $args{node_watcher} and $args{node_watcher}->isa('Lim::Plugin::Orr::Server::NodeWatcher')) {
        confess __PACKAGE__, ': Missing node_watcher or is not a Lim::Plugin::Orr::Server::NodeWatcher';
    }
    
    $self->{node_watcher} = $args{node_watcher};
    
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
    weaken($self);

    $self->{timer} = AnyEvent->timer(
        after => defined $after ? $after : $TIMER_INTERVAL,
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
    weaken($self);
    
    $self->{logger}->debug('Run() start');
    $self->{logger}->debug('Run() done');

    $self->Timer;
}

=item Add

=cut

sub Add {
    my $self = shift;
    my %args = ( @_ );

    unless (defined $args{cluster_uuid}) {
        $@ = 'Missing cluster_uuid';
        return;
    }

    return 1;
}

=item Remove

=cut

sub Remove {
    my ($self) = @_;
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

1; # End of Lim::Plugin::Orr::Server::ClusterManager
