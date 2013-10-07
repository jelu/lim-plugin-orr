package Lim::Plugin::Orr::Server::NodeWatcher;

use common::sense;

use Carp;
use Scalar::Util qw(weaken);
use AnyEvent ();
use Log::Log4perl ();

use Lim::Plugin::Orr ();
use Lim::Plugin::Orr::Server::NodeFactory ();

use base qw(Exporter);
our @EXPORT = qw(
    NODE_STATE_UNKNOWN
    NODE_STATE_OFFLINE
    NODE_STATE_ONLINE
    NODE_STATE_FAILURE
    NODE_STATE_STANDBY
    NODE_STATE_DISABLED
);

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

=item NODE_STATE_UNKNOWN

This is the first state of a node before anything is known about the node.

=item NODE_STATE_OFFLINE

Indicates that the node is not online.

=item NODE_STATE_ONLINE

Indicates that the node is online and operational.

=item NODE_STATE_FAILURE

Indicates that the node has failed and all processing for this node has stopped.
User intervention is needed at this state.

=item NODE_STATE_STANDBY

Indicates that a node has been in OFFLINE or FAILURE state but is now reachable
again but has not been included back into the cluster or is just standing by for
redundancy in case another node fails.

=item NODE_STATE_DISABLED

Indicates that the node is disabled and will not be used in the cluster.
Can only be set through manual actions.

=back

=cut

sub NODE_STATE_UNKNOWN  (){ 0 }
sub NODE_STATE_OFFLINE  (){ 1 }
sub NODE_STATE_ONLINE   (){ 2 }
sub NODE_STATE_FAILURE  (){ 3 }
sub NODE_STATE_STANDBY  (){ 4 }
sub NODE_STATE_DISABLED (){ 5 }

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
        # Ping the node if its offline or if its time to ping it again to check
        # that it is alive
        #
        if ($node->{state} == NODE_STATE_UNKNOWN or
            $node->{state} == NODE_STATE_OFFLINE or
            (($node->{state} == NODE_STATE_ONLINE or
              $node->{state} == NODE_STATE_STANDBY)
             and $node->{node}->LastCall < (time - $NODE_REPING)))
        {
            Lim::DEBUG and $self->{logger}->debug('Pinging node ', $node->{uuid});
            $node->{lock} = 1;
            $node->{node}->Ping(sub {
                my ($success) = @_;
                
                unless (defined $self) {
                    return;
                }
                
                if ($success) {
                    if ($node->{state} == NODE_STATE_UNKNOWN or $node->{state} == NODE_STATE_OFFLINE) {
                        Lim::DEBUG and $self->{logger}->debug('Node ', $node->{uuid}, ' STATE STANDBY');
                        $node->{state} = NODE_STATE_STANDBY;
                    }
                }
                else {
                    if ($node->{state} == NODE_STATE_ONLINE or $node->{state} == NODE_STATE_STANDBY or $node->{state} == NODE_STATE_UNKNOWN) {
                        Lim::DEBUG and $self->{logger}->debug('Node ', $node->{uuid}, ' STATE OFFLINE');
                        $node->{state} = NODE_STATE_OFFLINE;
                        $node->{cache} = {};
                    }
                }
                $node->{lock} = 0;
            });
            next;
        }
        
        #
        # Process Node work queue
        #
        if (defined (my $work = shift(@{$node->{queue}}))) {
            unless (ref($work) eq 'ARRAY') {
                confess __PACKAGE__, ': Node work not ARRAY';
            }
            
            my $what = shift(@$work);
            unless ($node->{node}->can($what)) {
                confess __PACKAGE__, ': Node work '.$what.' can not be done';
            }
            
            my $cb = shift(@$work);
            unless (ref($cb) eq 'CODE') {
                confess __PACKAGE__, ': Node work cb invalid';
            }
            
            if ($node->{state} == NODE_STATE_ONLINE or $node->{state} == NODE_STATE_STANDBY) {
                Lim::DEBUG and $self->{logger}->debug('Node ', $node->{uuid}, ' working on ', $what);
                $node->{lock} = 1;
                $node->{node}->$what(sub {
                    $cb->(@_);
                    $node->{lock} = 0;
                }, @$work);
                next;
            }
            else {
                $cb->();
            }
        }

        #
        # Remove node if its scheduled to be removed
        #
        if ($node->{remove}) {
            Lim::DEBUG and $self->{logger}->debug('Removed node ', $node->{uuid});
            delete $self->{node}->{$node->{uuid}};
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
        state => NODE_STATE_UNKNOWN,
        node => $node,
        remove => 0,
        cache => {},
        queue => []
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

        unless ($node->{state} == NODE_STATE_ONLINE or $node->{state} == NODE_STATE_STANDBY) {
            $result->{$uuid} = undef;
            next;
        }
        
        if (exists $node->{cache}->{versions}) {
            $result->{$uuid} = $node->{cache}->{versions};
            next;
        }
        
        push(@{$node->{queue}}, ['Versions', sub {
            my ($version) = @_;
            
            if (ref($version) eq 'HASH') {
                $node->{cache}->{versions} = $result->{$uuid} = $version;
            }
            else {
                $result->{$uuid} = undef;
            }
            $nodes--;
            
            unless ($nodes) {
                $cb->($result);
            }
        }]);
        $nodes++;
    }
    
    unless ($nodes) {
        $cb->($result);
    }
}

=item SetupHSM

=cut

sub SetupHSM {
    my ($self, $cb, $data) = @_;
    
    unless (ref($cb) eq 'CODE') {
        confess __PACKAGE__, ': Missing cb or is not CODE';
    }
    unless (ref($data) eq 'HASH') {
        confess __PACKAGE__, ': Missing data or is not HASH';
    }
    
    my $result = {};
    my $nodes = 0;
    foreach my $node (values %{$self->{node}}) {
        my $uuid = $node->{uuid};

        unless ($node->{state} == NODE_STATE_ONLINE or $node->{state} == NODE_STATE_STANDBY) {
            $result->{$uuid} = undef;
            next;
        }
        
        if (exists $node->{cache}->{hsm_setup}) {
            $result->{$uuid} = 1;
            next;
        }
        
        push(@{$node->{queue}}, ['SetupHSM', sub {
            my ($successful) = @_;
            
            if ($successful) {
                $node->{cache}->{hsm_setup} = $result->{$uuid} = 1;
            }
            else {
                $result->{$uuid} = undef;
            }
            $nodes--;
            
            unless ($nodes) {
                $cb->($result);
            }
        }, $data]);
        $nodes++;
    }
    
    unless ($nodes) {
        $cb->($result);
    }
}

=item SetupPolicy

=cut

sub SetupPolicy {
    my ($self, $cb) = @_;
    
    unless (ref($cb) eq 'CODE') {
        confess __PACKAGE__, ': Missing cb or is not CODE';
    }
    
    # TODO
}

=item NodeStates

=cut

sub NodeStates {
    my ($self) = @_;
    
    map { $_->{uuid} => $_->{state} } values %{$self->{node}};
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
