package Lim::Plugin::Orr::Server::NodeWatcher;

use common::sense;

use Carp;
use Scalar::Util qw(weaken);
use AnyEvent ();
use Log::Log4perl ();

use Lim::Plugin::Orr ();
use Lim::Plugin::Orr::Server::NodeFactory ();

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server::NodeWatcher - Node Watcher for the OpenDNSSEC
Redundancy Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;

our $TIMER_INTERVAL = 5;
our $NODE_REPING = 30;

=head1 SYNOPSIS

  use Lim::Plugin::Orr::Server::NodeWatcher;
  
  my $node_watcher = Lim::Plugin::Orr::Server::NodeWatcher->new(...);

=head1 DESCRIPTION

This is a Node Watcher for the OpenDNSSEC Redundancy Robot that will handle node
actions such as syncing information between nodes.

=head1 NODE STATES

=over 4

=item STATE_OFFLINE

=item STATE_ONLINE

=back

=cut

sub STATE_OFFLINE (){ 0 }
sub STATE_ONLINE  (){ 1 }

=head1 METHODS

These methods handles the nodes for OpenDNSSEC Redundancy Robot.

=over 4

=item $node_manager = Lim::Plugin::Orr::Server::NodeWatcher->new(...);

Create a new Node Watcher object for the OpenDNSSEC Redundancy Robot.

=cut

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my %args = ( @_ );
    my $self = {
        logger => Log::Log4perl->get_logger,
        node => {},
        
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
    foreach my $node (values %{$self->{node}}) {
        #
        # Skip locked nodes
        #
        if ($node->{lock}) {
            Lim::DEBUG and $self->{logger}->debug('Node ', $node->{uuid}, ' locked');
            next;
        }
        
        #
        # Remove node if its scheduled to be removed
        #
        if ($node->{remove}) {
            Lim::DEBUG and $self->{logger}->debug('Removed node ', $node->{uuid});
            delete $self->{node}->{$node->{uuid}};
            next;
        }
        
        #
        # Ping the node if its offline or if its time to ping it again to check
        # that it is alive
        #
        if ($node->{state} == STATE_OFFLINE or $node->{node}->LastCall < (time - $NODE_REPING)) {
            Lim::DEBUG and $self->{logger}->debug('Pinging node ', $node->{uuid});
            $node->{lock} = 1;
            $node->{node}->Ping(sub {
                my ($success) = @_;
                
                unless (defined $self) {
                    return;
                }
                
                if ($success) {
                    if ($node->{state} != STATE_ONLINE) {
                        Lim::DEBUG and $self->{logger}->debug('Node ', $node->{uuid}, ' STATE ONLINE');
                        $node->{state} = STATE_ONLINE;
                    }
                }
                else {
                    if ($node->{state} != STATE_OFFLINE) {
                        Lim::DEBUG and $self->{logger}->debug('Node ', $node->{uuid}, ' STATE OFFLINE');
                        $node->{state} = STATE_OFFLINE;
                    }
                }
                $node->{lock} = 0;
            });
            next;
        }
    }
    $self->{logger}->debug('Run() done');

    $self->Timer;
}

=item Add

=cut

sub Add {
    my $self = shift;
    my %args = ( @_ );

    unless (defined $args{uuid}) {
        $@ = 'Missing uuid';
        return;
    }
    unless (defined $args{uri}) {
        $@ = 'Missing uri';
        return;
    }
    
    if (exists $self->{node}->{$args{uuid}}) {
        $@ = 'A node with that UUID already exists';
        return;
    }
    
    my $node;
    eval {
        $node = Lim::Plugin::Orr::Server::NodeFactory->new(uri => $args{uri});
    };
    if ($@) {
        $@ = 'Unable to create Node object: '.$@;
        return;
    }
        
    Lim::DEBUG and $self->{logger}->debug('Adding ', $args{uuid}, ' at ', $args{uri});

    $self->{node}->{$args{uuid}} = {
        uuid => $args{uuid},
        uri => $args{uri},
        state => STATE_OFFLINE,
        node => $node,
        remove => 0
    };
    
    return 1;
}

=item Remove

=cut

sub Remove {
    my ($self, $uuid) = @_;
    
    if (exists $self->{node}->{$uuid}) {
        Lim::DEBUG and $self->{logger}->debug('Removing ', $uuid);
        
        $self->{node}->{$uuid}->{remove} = 1;
    }
}

=item Versions

=cut

sub Versions {
    my ($self, $cb) = @_;
    
    unless (ref($cb) eq 'CODE') {
        confess __PACKAGE__, ': Missing cb or is not CODE';
    }
    
    my $result = {};
    my $nodes = 0;
    foreach my $node (values %{$self->{node}}) {
        my $uuid = $node->{uuid};

        if ($node->{state} == STATE_OFFLINE) {
            $result->{$uuid} = undef;
            next;
        }
        
        $node->{node}->Versions(sub {
            my ($version) = @_;
            
            if (ref($version) eq 'HASH') {
                $result->{$uuid} = $version;
            }
            $nodes--;
            
            unless ($nodes) {
                $cb->($result);
            }
        });
        $nodes++;
    }
    
    unless ($nodes) {
        $cb->($result);
    }
}

=item AnyOnline

=cut

sub AnyOnline {
    my ($self) = @_;
    
    foreach my $node (values %{$self->{node}}) {
        if ($node->{state} == STATE_ONLINE) {
            return 1;
        }
    }
    
    return;
}

=item ZoneAdd

=cut

sub ZoneAdd {
    my $self = shift;
    my %args = ( @_ );
    
    unless (defined $args{name}) {
        confess __PACKAGE__, ': Missing name';
    }
    unless (defined $args{content}) {
        confess __PACKAGE__, ': Missing content';
    }
    unless (exists $args{cb} and ref($args{cb}) eq 'CODE') {
        confess __PACKAGE__, ': Missing cb or is not CODE';
    }

    # TODO
}

=back

=head1 AUTHOR

Jerry Lundström, C<< <lundstrom.jerry at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to L<https://github.com/jelu/lim-plugin-orr/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lim::Plugin::Orr::Server::NodeWatcher

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
