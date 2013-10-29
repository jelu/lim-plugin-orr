package Lim::Plugin::Orr::Server::ClusterManager;

use common::sense;

use Carp;
use Scalar::Util qw(weaken blessed);
use AnyEvent ();
use Log::Log4perl ();
use XML::LibXML ();

use Lim::Plugin::Orr ();
use Lim::Plugin::Orr::Server::NodeWatcher qw(:DEFAULT);
use Lim::Plugin::Orr::Server::ZoneInput ();

use base qw(Exporter);
our @EXPORT = qw(
    CLUSTER_STATE_INITIALIZING
    CLUSTER_STATE_OPERATIONAL
    CLUSTER_STATE_DEGRADED
    CLUSTER_STATE_DISFUNCTIONAL
    CLUSTER_STATE_FAILURE
    CLUSTER_STATE_DISABLED
);

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server::ClusterManager - Cluster Manager for the OpenDNSSEC
Redundancy Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;
our $TIMER_INTERVAL_MAX = 10;
our $SOFTWARE_VERSION = {
    plugin => {
        Agent => { min => '0.19', max => '0.19', required => 1 },
        OpenDNSSEC => { min => '0.14', max => '0.14', required => 1 },
        SoftHSM => { min => '0.14', max => '0.14', required => 0 },
        DNS => { min => '0.12', max => '0.12', required => 0 },
    },
    program => {
        'ods-control' => { min => '1', max => '1', required => 1 },
        'ods-signerd' => { min => '1.3.14', max => '1.3.15', required => 1 },
        'ods-signer' => { min => '1.3.14', max => '1.3.15', required => 1 },
        'ods-enforcerd' => { min => '1.3.14', max => '1.3.15', required => 1 },
        'ods-ksmutil' => { min => '1.3.14', max => '1.3.15', required => 1 },
        'ods-hsmutil' => { min => '1.3.14', max => '1.3.15', required => 0 },
        'softhsm' => { min => '1.3.3', max => '1.3.5', required => 0 }
    }
};

=head1 SYNOPSIS

  use Lim::Plugin::Orr::Server::ClusterManager;
  
  my $cluster_manager = Lim::Plugin::Orr::Server::ClusterManager->new(...);

=head1 DESCRIPTION

This is a Cluster Manager for the OpenDNSSEC Redundancy Robot that will ...

=head1 CLUSTER STATES

=over 4

=item CLUSTER_STATE_INITIALIZING

The first state of a cluster and it happens when you first start a cluster, when
a configuration change has been made on a cluster, when a cluster is recovering
from DEGRADED state or brought back from a FAILURE/DISABLED state.
For example this state will (re)initialize all configuration on all nodes, check
for updated zone content and push that out.

=item CLUSTER_STATE_OPERATIONAL

This is the state when everything is up and running as it should. It will 
continuously check for zone content updates, push that out if there are updates,
manager ZSK/KSK synchronization/rollovers and push signed zone contents to
configured outputs.

=item CLUSTER_STATE_DEGRADED

This state is much like OPERATIONAL but part of the cluster is not working as it
should but enough is working to continue. This can happen if a node can't be
reached or is failing.

=item CLUSTER_STATE_DISFUNCTIONAL

This state is when the cluster is not working but no fatal problems has occurred
so it will be able to recover later on.

=item CLUSTER_STATE_FAILURE

This is a serious and fatal state, something happened so that the cluster can
not continue and has stopped all processing.
User intervention is needed at this state since the cluster can not repair it
self.

=item CLUSTER_STATE_DISABLED

This indicates that the cluster is disabled.
Can only be set through manual actions.

=back

=cut

sub CLUSTER_STATE_INITIALIZING  (){ 0 }
sub CLUSTER_STATE_OPERATIONAL   (){ 1 }
sub CLUSTER_STATE_DEGRADED      (){ 2 }
sub CLUSTER_STATE_DISFUNCTIONAL (){ 3 }
sub CLUSTER_STATE_FAILURE       (){ 4 }
sub CLUSTER_STATE_DISABLED      (){ 5 }
our %CLUSTER_STATE = (
    CLUSTER_STATE_INITIALIZING() => 'INITIALIZING',
    CLUSTER_STATE_OPERATIONAL() => 'OPERATIONAL',
    CLUSTER_STATE_DEGRADED() => 'DEGRADED',
    CLUSTER_STATE_DISFUNCTIONAL() => 'DISFUNCTIONAL',
    CLUSTER_STATE_FAILURE() => 'FAILURE',
    CLUSTER_STATE_DISABLED() => 'DISABLED'
);

=head1 CLUSTER MODES

=over 4

=item CLUSTER_MODE_BACKUP

=item CLUSTER_MODE_FAILOVER

=item CLUSTER_MODE_BALANCE

=cut

sub CLUSTER_MODE_BACKUP   (){ 0 }
sub CLUSTER_MODE_FAILOVER (){ 1 }
sub CLUSTER_MODE_BALANCE  (){ 2 }
our %CLUSTER_MODE = (
    CLUSTER_MODE_BACKUP() => 'BACKUP',
    CLUSTER_MODE_FAILOVER() => 'FAILOVER',
    CLUSTER_MODE_BALANCE() => 'BALANCE'
);

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
        logger => Log::Log4perl->get_logger,
        zone => {},
        lock => 0,
        state => CLUSTER_STATE_INITIALIZING,
        state_timestamp => time,
        cache => {},
        log => [],
        interval => 0
    };
    bless $self, $class;

    unless (defined $args{uuid}) {
        confess __PACKAGE__, ': Missing uuid';
    }
    unless (defined $args{mode}) {
        confess __PACKAGE__, ': Missing mode';
    }
    foreach (keys %CLUSTER_MODE) {
        if ($args{mode} eq $CLUSTER_MODE{$_}) {
            $self->{mode} = $CLUSTER_MODE{$_};
        }
    }
    unless (exists $self->{mode}) {
        confess __PACKAGE__, ': mode is invalid';
    }

    unless (exists $args{policy} and ref($args{policy}) eq 'HASH') {
        confess __PACKAGE__, ': Missing policy or not HASH';
    }
    unless (defined $args{policy}->{uuid}) {
        confess __PACKAGE__, ': Missing policy->uuid';
    }
    unless (defined $args{policy}->{data}) {
        confess __PACKAGE__, ': Missing policy->data';
    }
    # TODO validate data
    $self->{policy} = $args{policy};

    unless (exists $args{hsms} and ref($args{hsms}) eq 'ARRAY') {
        confess __PACKAGE__, ': Missing hsm or not ARRAY';
    }
    foreach (@{$args{hsms}}) {
        unless (ref($_) eq 'HASH') {
            confess __PACKAGE__, ': hsm item is not an hash ref';
        }

        foreach my $k (qw(uuid data)) {
            unless (exists $_->{$k}) {
                confess __PACKAGE__, ': Missing ', $k, ' in hsm item';
            }
        }
        
        # TODO validate data
    }
    $self->{hsms} = $args{hsms};
    
    if (exists $args{zones}) {
        unless (ref($args{zones}) eq 'ARRAY') {
            confess __PACKAGE__, ': zones is not an array ref';
        }
        
        foreach (@{$args{zones}}) {
            unless ($self->ZoneAdd($_)) {
                confess __PACKAGE__, ': ', $@;
            }
        }
    }

    $self->{uuid} = $args{uuid};
    $self->{node_watcher} = Lim::Plugin::Orr::Server::NodeWatcher->new;
    
    if (exists $args{nodes}) {
        unless (ref($args{nodes}) eq 'ARRAY') {
            confess __PACKAGE__, ': nodes is not an array ref';
        }
        
        foreach (@{$args{nodes}}) {
            unless (ref($_) eq 'HASH') {
                confess __PACKAGE__, ': node item is not an hash ref';
            }
            
            unless ($self->{node_watcher}->Add(%$_)) {
                confess __PACKAGE__, ': unable to add node to NodeWatcher: ', $@;
            }
        }
    }

    $self->{node_watcher}->Timer;
    $self->Timer;

    Lim::OBJ_DEBUG and $self->{logger}->debug('new ', __PACKAGE__, ' ', $self);
    $self;
}

sub DESTROY {
    my ($self) = @_;
    Lim::OBJ_DEBUG and $self->{logger}->debug('destroy ', __PACKAGE__, ' ', $self);
    
    $self->Stop;
}

=item uuid

=cut

sub uuid {
    $_[0]->{uuid};
}

=item mode

=cut

sub mode {
    $_[0]->{mode};
}

=item zones

=cut

sub zones {
    values %{$_[0]->{zone}};
}

=item NodeWatcher

=cut

sub NodeWatcher {
    $_[0]->{node_watcher};
}

=item Timer

=cut

sub Timer {
    my ($self, $after) = @_;
    weaken($self);

    $self->{timer} = AnyEvent->timer(
        after => defined $after ? $after : $self->{interval},
        cb => sub {
            defined $self and $self->Run;
        });
}

=item IncInterval

=cut

sub IncInterval {
    my ($self) = @_;
    
    $self->{interval}++;

    if ($self->{interval} > $TIMER_INTERVAL_MAX) {
        $self->{interval} = $TIMER_INTERVAL_MAX;
    }
}

=item ResetInterval

=cut

sub ResetInterval {
    $_[0]->{interval} = 0;
}

=item Stop

=cut

sub Stop {
    my ($self) = @_;

    Lim::DEBUG and $self->{logger}->debug($self->{uuid}, ': Stop()');
    
    delete $self->{timer};
}

=item Run

=cut

sub Run {
    my ($self) = @_;
    weaken($self);

    if ($self->{lock} or $self->{state} == CLUSTER_STATE_FAILURE) {
        $self->IncInterval;
        $self->Timer;
        return;
    }
    
    #
    # Check if we are reseting all states, this happend when adding or removing
    # nodes.
    #
    if (exists $self->{cache}->{reset}) {
        $self->State(CLUSTER_STATE_INITIALIZING, 'Resetting');
        $self->{cache} = {};
        foreach my $zone (values %{$self->{zone}}) {
            $zone->{cache} = {};
        }
    }

    #
    # At start when INITIALIZING, wait for all nodes to come out from UNKNOWN
    #
    if ($self->{state} == CLUSTER_STATE_INITIALIZING) {
        my %states = $self->{node_watcher}->NodeStates;
        foreach (values %states) {
            if ($_ == NODE_STATE_UNKNOWN) {
                $self->IncInterval;
                $self->Timer;
                return;
            }
        }
    }
    
    Lim::DEBUG and $self->{logger}->debug($self->{uuid}, ': Run() start');

    #
    # Verify Node versions
    #
    unless (exists $self->{cache}->{version}) {
        $self->Log('Fetching version information from nodes');
        $self->{lock} = 1;
        $self->{node_watcher}->Versions(sub {
            my ($result) = @_;
            
            unless (defined $self) {
                return;
            }
            
            unless (ref($result) eq 'HASH') {
                $self->State(CLUSTER_STATE_FAILURE, 'Unable to retrieve versions of software running, result set returned is invalid.');
                $self->{lock} = 0;
                return;
            }
            
            my $error;
            foreach my $node_uuid (keys %$result) {
                unless (defined $result->{$node_uuid}) {
                    $self->Log('Unable to retrieve version for node ', $node_uuid);
                    $error++;
                    next;
                }
                unless (ref($result->{$node_uuid}) eq 'HASH') {
                    $self->State(CLUSTER_STATE_FAILURE, 'Unable to retrieve versions of software running on node ', $node_uuid, ': structure is invalid');
                    $self->{lock} = 0;
                    return;
                }
                my $node = $result->{$node_uuid};
                
                foreach my $what (qw(plugin program)) {
                    unless (exists $node->{$what} and ref($node->{$what}) eq 'HASH') {
                        $self->State(CLUSTER_STATE_FAILURE, 'Unable to retrieve versions of software running on node ', $node_uuid, ': structure for ', $what, ' is invalid');
                        $self->{lock} = 0;
                        return;
                    }
                    
                    foreach my $entry (keys %{$SOFTWARE_VERSION->{$what}}) {
                        unless (exists $node->{$what}->{$entry}) {
                            if ($SOFTWARE_VERSION->{$what}->{$entry}->{required}) {
                                $self->Log('Missing required software ', $entry, ' for node ', $node_uuid);
                                $self->{node_watcher}->NodeState($node_uuid, NODE_STATE_FAILURE);
                                $error++;
                            }
                            next;
                        }
                        
                        if (($SOFTWARE_VERSION->{$what}->{$entry}->{min} gt
                             $node->{$what}->{$entry}) or
                            ($SOFTWARE_VERSION->{$what}->{$entry}->{max} lt
                             $node->{$what}->{$entry}))
                        {
                            $self->Log('Software ', $entry, ' version ', $node->{$what}->{$entry}, ' on node ', $node_uuid,
                                ' is not supported. Supported are minimum version ', $SOFTWARE_VERSION->{$what}->{$entry}->{min},
                                ' and maximum version ', $SOFTWARE_VERSION->{$what}->{$entry}->{max});
                            $self->{node_watcher}->NodeState($node_uuid, NODE_STATE_FAILURE);
                            $error++;
                        }
                    }
                }
            }
            $self->{cache}->{version} = $result;
            if ($error) {
                $self->Log('Version information problems on ', $error, ' nodes');
            }
            else {
                $self->Log('Version information correct and supported');
            }
            
            $self->ResetInterval;
            $self->Timer;
            $self->{lock} = 0;
        });
        $self->ResetInterval;
        $self->Timer;
        return;
    }
    
    #
    # Setup cache for nodes that will need reload later
    #
    unless (exists $self->{cache}->{reload}) {
        $self->{cache}->{reload} = {};
    }
    
    #
    # Configure/Initiate/Verify HSM
    #
    unless (exists $self->{cache}->{hsms_setup}) {
        unless (exists $self->{cache}->{hsm_setup} and ref($self->{cache}->{hsm_setup}) eq 'HASH') {
            $self->{cache}->{hsm_setup} = {};
        }
        
        foreach my $hsm (@{$self->{hsms}}) {
            if (exists $self->{cache}->{hsm_setup}->{$hsm}) {
                next;
            }

            $self->Log('Setting up HSM ', $hsm->{uuid});

            $self->{lock} = 1;
            $self->{node_watcher}->SetupHSM(sub {
                my ($result) = @_;
                
                unless (defined $self) {
                    return;
                }
                
                $self->{cache}->{hsm_setup}->{$hsm} = $result;
                $self->{lock} = 0;
            }, $hsm->{data});
            $self->ResetInterval;
            $self->Timer;
            return;
        }

        my $error;
        foreach my $hsm (@{$self->{hsms}}) {
            my $result = $self->{cache}->{hsm_setup}->{$hsm};
            
            unless (ref($result) eq 'HASH') {
                $self->State(CLUSTER_STATE_FAILURE, 'Unable to setup HSM ', $hsm->{uuid} ,', result set returned is invalid.');
                $self->{lock} = 0;
                return;
            }
            
            foreach my $node_uuid (keys %$result) {
                unless (defined $result->{$node_uuid}) {
                    $self->Log('Unable to setup HSM ',  $hsm->{uuid}, ' on node ', $node_uuid);
                    $error++;
                    next;
                }
                
                if ($result->{$node_uuid}) {
                    $self->{cache}->{reload}->{$node_uuid} = 1;
                    $self->{cache}->{hsms_setup} = 1;
                }
            }
        }
        
        unless (exists $self->{cache}->{hsms_setup}) {
            $self->{cache}->{hsms_setup} = 0;
        }

        if ($error) {
            $self->Log('HSMs setup problems on ', $error, ' nodes');
        }
        else {
            $self->Log('All HSMs setup ok');
        }
    }
    
    #
    # Configure/Initiate/Verify Policy
    #
    unless (exists $self->{cache}->{policy_setup}) {
        $self->Log('Setting up Policy ', $self->{policy}->{uuid});

        $self->{lock} = 1;
        $self->{node_watcher}->SetupPolicy(sub {
            my ($result) = @_;
            
            unless (defined $self) {
                return;
            }
            
            unless (ref($result) eq 'HASH') {
                $self->State(CLUSTER_STATE_FAILURE, 'Unable to setup Policy ',  $self->{policy}->{uuid}, ', result set returned is invalid.');
                $self->{lock} = 0;
                return;
            }
            
            my $error;
            foreach my $node_uuid (keys %$result) {
                unless (defined $result->{$node_uuid}) {
                    $self->Log('Unable to setup Policy ', $self->{policy}->{uuid}, ' on node ', $node_uuid);
                    $error++;
                    next;
                }
                
                if ($result->{$node_uuid}) {
                    $self->{cache}->{reload}->{$node_uuid} = 1;
                    $self->{cache}->{policy_setup} = 1;
                }
            }
            
            unless (exists $self->{cache}->{policy_setup}) {
                $self->{cache}->{policy_setup} = 0;
            }

            if ($error) {
                $self->Log('Policy setup problems on ', $error, ' nodes');
            }
            else {
                $self->Log('Policy setup ok');
            }

            $self->{lock} = 0;
            $self->ResetInterval;
        }, $self->{policy}->{data});
        $self->ResetInterval;
        $self->Timer;
        return;
    }

    # TODO need to handle OpenDNSSEC installations that are not setup yet
    
    #
    # Verfiy that OpenDNSSEC is running, start if not
    #
    unless (exists $self->{cache}->{running}) {
        $self->Log('Verifying OpenDNSSEC is running and starting if not');

        $self->{lock} = 1;
        $self->{node_watcher}->StartOpenDNSSEC(sub {
            my ($result) = @_;
            
            unless (defined $self) {
                return;
            }
            
            unless (ref($result) eq 'HASH') {
                $self->State(CLUSTER_STATE_FAILURE, 'Unable to verify or start OpenDNSSEC, result set returned is invalid.');
                $self->{lock} = 0;
                return;
            }
            
            my $error;
            foreach my $node_uuid (keys %$result) {
                unless (defined $result->{$node_uuid}) {
                    $self->Log('Unable to verify or start OpenDNSSEC on node ', $node_uuid);
                    $error++;
                }
            }
            
            $self->{cache}->{running} = 1;
            
            if ($error) {
                $self->Log('Verifying or starting OpenDNSSEC problems on ', $error, ' nodes')
            }
            else {
                $self->Log('OpenDNSSEC start ok');
            }
            
            $self->{lock} = 0;
            $self->ResetInterval;
        });
        $self->ResetInterval;
        $self->Timer;
        return;
    }
    
    #
    # Reload OpenDNSSEC on nodes that need it
    #
    if (%{$self->{cache}->{reload}}) {
        $self->Log('Reload OpenDNSSEC on nodes that need it');

        $self->{lock} = 1;
        $self->{node_watcher}->ReloadOpenDNSSEC(sub {
            my ($result) = @_;
            
            unless (defined $self) {
                return;
            }
            
            unless (ref($result) eq 'HASH') {
                $self->State(CLUSTER_STATE_FAILURE, 'Unable to reload OpenDNSSEC, result set returned is invalid.');
                $self->{lock} = 0;
                return;
            }
            
            my $error;
            foreach my $node_uuid (keys %$result) {
                unless (defined $result->{$node_uuid}) {
                    $self->Log('Unable to reload OpenDNSSEC on node ', $node_uuid);
                    $error++;
                }
            }
            
            if ($error) {
                $self->Log('Reload problems on ', $error, ' nodes');
            }
            else {
                $self->Log('Reload ok');
            }
            
            $self->{lock} = 0;
            $self->ResetInterval;
        }, keys %{$self->{cache}->{reload}});
        $self->{cache}->{reload} = {};
        $self->ResetInterval;
        $self->Timer;
        return;
    }

    #
    # Calculate cluster state based on information gathered so far
    #
    {
        my ($total, $failure, $offline, $standby, %state) = (0, 0, 0, 0);
        %state = $self->{node_watcher}->NodeStates;
        foreach my $node_uuid (keys %state) {
            $total++;
            
            if ($state{$node_uuid} == NODE_STATE_UNKNOWN) {
                confess __PACKAGE__, ': Node ', $node_uuid, ' in UNKNOWN state, this should not be possible here';
            }
            elsif ($state{$node_uuid} == NODE_STATE_OFFLINE) {
                $offline++;
            }
            elsif ($state{$node_uuid} == NODE_STATE_ONLINE) {
            }
            elsif ($state{$node_uuid} == NODE_STATE_FAILURE) {
                $failure++;
            }
            elsif ($state{$node_uuid} == NODE_STATE_STANDBY) {
                if ($self->{state} == CLUSTER_STATE_INITIALIZING) {
                    $self->Log('Upgrading node ', $node_uuid, ' from STANDBY to ONLINE');
                    $self->{node_watcher}->NodeState($node_uuid, NODE_STATE_ONLINE);
                }
                else {
                    $standby++;
                }
            }
            elsif ($state{$node_uuid} == NODE_STATE_DISABLED) {
                $offline++;
            }
            else {
                $self->State(CLUSTER_STATE_FAILURE, 'Unknown node state ', $state{$node_uuid}, ' for node ', $node_uuid);
                return;
            }
        }
        
        if ($standby) {
            unless ($self->{state} == CLUSTER_STATE_INITIALIZING) {
                $self->State(CLUSTER_STATE_INITIALIZING, 'Cluster (re)initializing because of nodes in STANDBY state');
                $self->{cache} = {};
                foreach my $zone (values %{$self->{zone}}) {
                    $zone->{cache} = {};
                }
                $self->ResetInterval;
            }
        }
        elsif ($failure or $offline) {
            if ($total == $failure) {
                $self->State(CLUSTER_STATE_FAILURE, 'All nodes FAILURE');
            }
            else {
                if ($self->{state} == CLUSTER_STATE_OPERATIONAL) {
                    $self->State(CLUSTER_STATE_DEGRADED, 'Nodes failure:', $failure, ' offline:', $offline);
                }
            }
        }
        else {
            unless ($self->{state} == CLUSTER_STATE_OPERATIONAL) {
                $self->State(CLUSTER_STATE_OPERATIONAL, 'Cluster operational');
            }
        }
        
        #
        # If cluster state is OPERATIONAL or DEGRADED, figure out per cluster
        # mode if we have enough nodes to work with
        #
        unless ($self->{state} == CLUSTER_STATE_OPERATIONAL or $self->{state} == CLUSTER_STATE_DEGRADED) {
            if ($self->{mode} == CLUSTER_MODE_BACKUP) {
                
            }
            elsif ($self->{mode} == CLUSTER_MODE_FAILOVER) {
                
            }
            elsif ($self->{mode} == CLUSTER_MODE_BALANCE) {
                
            }
            else {
                $self->State(CLUSTER_STATE_FAILURE, 'Unknown state');
                return;
            }
        }
    }
    
    #
    # Don't continue unless cluster is OPERATIONAL or DEGRADED
    #
    unless ($self->{state} == CLUSTER_STATE_OPERATIONAL or $self->{state} == CLUSTER_STATE_DEGRADED) {
        Lim::DEBUG and $self->{logger}->debug($self->{uuid}, ': Run() stopped, state ', $CLUSTER_STATE{$self->{state}});
        $self->Timer;
        return;
    }
    
    #
    # Process zones
    #
    foreach my $zone (values %{$self->{zone}}) {
        #
        # Skip locked zones
        #
        if ($zone->{lock}) {
            Lim::DEBUG and $self->{logger}->debug($self->{uuid}, ': Zone ', $zone->{uuid}, ' locked');
            next;
        }
        
        #
        # Fetch zone content
        #
        unless (exists $zone->{cache}->{content}) {
            $self->Log('Fetching zone content for zone ', $zone->{uuid});
            $zone->{lock} = 1;
            $zone->{input}->Fetch(sub {
                my ($content) = @_;
                
                unless (defined $self) {
                    return;
                }
                
                unless (defined $content) {
                    $self->State(CLUSTER_STATE_FAILURE, 'Unable to fetch zone ', $zone->{uuid}, ' content');
                    $zone->{lock} = 0;
                    return;
                }
                
                $self->Log('Zone content for zone ', $zone->{uuid}, ' fetched');
                $zone->{cache}->{content} = $content;
                $zone->{cache}->{fetched} = AnyEvent->now;
                delete $zone->{cache}->{updated};
                $zone->{lock} = 0;
                $self->ResetInterval;
            });
            $self->ResetInterval;
            next;
        }
        
        #
        # Configure/Initiate/Verify Zone
        #
        unless (exists $zone->{cache}->{setup}) {
            $self->Log('Setting up zone ', $zone->{uuid});
            $zone->{lock} = 1;
            $self->{node_watcher}->ZoneAdd(sub {
                my ($result) = @_;
                
                unless (defined $self) {
                    return;
                }
                
                unless (ref($result) eq 'HASH') {
                    $self->State(CLUSTER_STATE_FAILURE, 'Unable to setup zone ',  $zone->{uuid}, ', result set returned is invalid.');
                    $zone->{lock} = 0;
                    return;
                }
                
                my $error;
                foreach my $node_uuid (keys %$result) {
                    unless (defined $result->{$node_uuid}) {
                        $self->Log('Unable to setup zone ', $zone->{uuid}, ' on node ', $node_uuid);
                        $error = 1;
                    }
                }
                
                $zone->{cache}->{setup} = 1;
                
                if ($error) {
                    $self->Log('Zone ', $zone->{uuid}, ' setup problems on ', $error, ' nodes');
                }
                else {
                    $self->Log('Zone ', $zone->{uuid}, ' setup ok');
                }
                
                $zone->{lock} = 0;
                $self->ResetInterval;
            }, $zone->{name}, $zone->{cache}->{content}, $self->{policy}->{data});
            $self->ResetInterval;
            next;
        }

        #
        # Roll KSK
        #
        
        #
        # Sync KSK
        #
        
        #
        # Roll ZSK
        #

        #
        # Sync ZSK
        #
        
        #
        # Update Zone
        #
        
        #
        # Fetch signed zone
        #
    }
    
    Lim::DEBUG and $self->{logger}->debug($self->{uuid}, ': Run() done');
    $self->IncInterval;
    $self->Timer;
}

=item Log

=cut

sub Log {
    my $self = shift;
    my $log = join('', @_);
    
    Lim::INFO and $self->{logger}->info($self->{uuid}, ': ', $log);
    push(@{$self->{log}}, time, $log);
}

=item State

=cut

sub State {
    my $self = shift;
    my $state = shift;
    
    if ($state == CLUSTER_STATE_INITIALIZING) {
        if ($self->{state} == CLUSTER_STATE_FAILURE) {
            $self->Log('(State INITIALIZING) ', @_);
            return;
        }
        else {
            $self->Log('State INITIALIZING: ', @_);
        }
    }
    elsif ($state == CLUSTER_STATE_OPERATIONAL) {
        if ($self->{state} == CLUSTER_STATE_FAILURE) {
            $self->Log('(State OPERATIONAL) ', @_);
            return;
        }
        else {
            $self->Log('State OPERATIONAL: ', @_);
        }
    }
    elsif ($state == CLUSTER_STATE_DEGRADED) {
        if ($self->{state} == CLUSTER_STATE_FAILURE) {
            $self->Log('(State DEGRADED) ', @_);
            return;
        }
        else {
            $self->Log('State DEGRADED: ', @_);
        }
    }
    elsif ($state == CLUSTER_STATE_FAILURE) {
        $self->Log('State FAILURE: ', @_);
        $self->{cache} = {};
    }
    elsif ($state == CLUSTER_STATE_DISABLED) {
        $self->Log('State DISABLED: ', @_);
        $self->{cache} = {};
    }
    else {
        confess __PACKAGE__, ': Unable to change state to ', $state, ': Invalid state';
    }
    
    $self->{state} = $state;
    $self->{state_timestamp} = time;
}

=item NodeAdd

=cut

sub NodeAdd {
    my $self = shift;
    
    if ($self->{node_watcher}->NodeAdd(@_)) {
        $self->{cache}->{reset} = 1;
    }
}

=item NodeRemove

=cut

sub NodeRemove {
    my $self = shift;
    
    if ($self->{node_watcher}->NodeRemove(@_)) {
        $self->{cache}->{reset} = 1;
    }
}

=item ZoneAdd

=cut

sub ZoneAdd {
    my $self = shift;
    
    foreach (@_) {
        unless (ref($_) eq 'HASH') {
            $@ = 'Zone is not an hash ref';
            return;
        }
        
        my $zone = {
            cache => {}
        };
        
        foreach my $k (qw(uuid name input_type input_data)) {
            unless (exists $_->{$k}) {
                $@ = 'Missing '.$k.' in zone item';
                return;
            }
            
            $zone->{$k} = $_->{$k};
        }
        
        if (exists $self->{zone}->{$_->{uuid}}) {
            $@ = 'Zone '.$_->{uuid}.' already exists';
            return;
        }

        eval {
            $zone->{input} = Lim::Plugin::Orr::Server::ZoneInput->new(
                zone => $_->{name},
                type => $_->{input_type},
                data => $_->{input_data}
            );
        };
        if ($@) {
            return;
        }
        
        $self->{zone}->{$_->{uuid}} = $zone;
    }
    
    return 1;
}

=item ZoneRemove

=cut

sub ZoneRemove {
    my ($self, $zone_uuid) = @_;
    
    unless (exists $self->{zone}->{$zone_uuid}) {
        $@ = 'Zone does not exists';
        return;
    }
    
    $self->{zone}->{$zone_uuid}->{remove} = 1;
    return 1;
}

=back

=head1 AUTHOR

Jerry Lundström, C<< <lundstrom.jerry at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to L<https://github.com/jelu/lim-plugin-orr/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lim::Plugin::Orr::Server::ClusterManager

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
