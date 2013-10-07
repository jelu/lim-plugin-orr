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
our $TIMER_INTERVAL = 5;
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

sub CLUSTER_STATE_INITIALIZING (){ 0 }
sub CLUSTER_STATE_OPERATIONAL  (){ 1 }
sub CLUSTER_STATE_DEGRADED     (){ 2 }
sub CLUSTER_STATE_FAILURE      (){ 3 }
sub CLUSTER_STATE_DISABLED     (){ 4 }

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
        state_message => undef,
        cache => {}
    };
    bless $self, $class;

    unless (defined $args{uuid}) {
        confess __PACKAGE__, ': Missing uuid';
    }
    unless (defined $args{mode}) {
        confess __PACKAGE__, ': Missing mode';
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
    # TODO validate XML
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
        
        # TODO validate XML
    }
    $self->{hsms} = $args{hsms};
    
    if (exists $args{zones}) {
        unless (ref($args{zones}) eq 'ARRAY') {
            confess __PACKAGE__, ': zones is not an array ref';
        }
        
        foreach (@{$args{zones}}) {
            unless (ref($_) eq 'HASH') {
                confess __PACKAGE__, ': zone item is not an hash ref';
            }
            
            foreach my $k (qw(uuid name input_type input_data)) {
                unless (exists $_->{$k}) {
                    confess __PACKAGE__, ': Missing ', $k, ' in zone item';
                }
            }
            
            if (exists $self->{zone}->{$_->{uuid}}) {
                confess __PACKAGE__, ': zone item already exists';
            }
            
            $self->{zone}->{$_->{uuid}} = $_;
            $self->{zone}->{$_->{uuid}}->{input} = Lim::Plugin::Orr::Server::ZoneInput->new(
                zone => $_->{name},
                type => $_->{input_type},
                data => $_->{input_data}
            );
        }
    }

    $self->{uuid} = $args{uuid};
    $self->{mode} = $args{mode};
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

    $self->{node_watcher}->Timer(0);
    $self->Timer(0);

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
        after => defined $after ? $after : $TIMER_INTERVAL,
        cb => sub {
            defined $self and $self->Run;
        });
}

=item Stop

=cut

sub Stop {
    my ($self) = @_;

    $self->{logger}->debug($self->{uuid}, ': Stop()');
    
    delete $self->{timer};
}

=item Run

=cut

sub Run {
    my ($self) = @_;
    weaken($self);

    if ($self->{lock} or $self->{state} == CLUSTER_STATE_FAILURE) {
        $self->Timer;
        return;
    }

    #
    # At start when INITIALIZING, wait for all nodes to come out from UNKNOWN
    #
    if ($self->{state} == CLUSTER_STATE_INITIALIZING) {
        my %states = $self->{node_watcher}->NodeStates;
        foreach (values %states) {
            if ($_ == NODE_STATE_UNKNOWN) {
                $self->Timer;
                return;
            }
        }
    }
    
    #
    #
    #
    $self->{logger}->debug($self->{uuid}, ': Run() start');

    #
    # Verify Node versions
    #
    unless (exists $self->{cache}->{version}) {
        Lim::DEBUG and $self->{logger}->debug($self->{uuid}, ': Fetching version information from nodes');
        $self->{lock} = 1;
        $self->{node_watcher}->Versions(sub {
            my ($result) = @_;
            
            unless (defined $self) {
                return;
            }
            
            if (ref($result) eq 'HASH') {
                foreach my $node_uuid (keys %$result) {
                    unless (ref($result->{$node_uuid}) eq 'HASH') {
                        $self->{state} = CLUSTER_STATE_FAILURE;
                        $self->{state_message} = 'Unable to retrieve versions of software running on node '.$node_uuid.': no versions returned';
                        $self->{cache} = {};
                        $self->{lock} = 0;
                        Lim::WARN and $self->{logger}->warn($self->{uuid}, ': FAILURE: ', $self->{state_message});
                        return;
                    }
                    my $node = $result->{$node_uuid};
                    
                    foreach my $what (qw(plugin program)) {
                        unless (exists $node->{$what} and ref($node->{$what}) eq 'HASH') {
                            $self->{state} = CLUSTER_STATE_FAILURE;
                            $self->{state_message} = 'Unable to retrieve versions of software running on node '.$node_uuid.': structure for '.$what.' is invalid';
                            $self->{cache} = {};
                            $self->{lock} = 0;
                            Lim::WARN and $self->{logger}->warn($self->{uuid}, ': FAILURE: ', $self->{state_message});
                            return;
                        }
                        
                        foreach my $entry (keys %{$SOFTWARE_VERSION->{$what}}) {
                            unless (exists $node->{$what}->{$entry}) {
                                if ($SOFTWARE_VERSION->{$what}->{$entry}->{required}) {
                                    $self->{state} = CLUSTER_STATE_FAILURE;
                                    $self->{state_message} = 'Missing required software '.$entry.' for node '.$node_uuid;
                                    $self->{cache} = {};
                                    $self->{lock} = 0;
                                    Lim::WARN and $self->{logger}->warn($self->{uuid}, ': FAILURE: ', $self->{state_message});
                                    return;
                                }
                                next;
                            }
                            
                            if (($SOFTWARE_VERSION->{$what}->{$entry}->{min} gt
                                 $node->{$what}->{$entry}) or
                                ($SOFTWARE_VERSION->{$what}->{$entry}->{max} lt
                                 $node->{$what}->{$entry}))
                            {
                                $self->{state} = CLUSTER_STATE_FAILURE;
                                $self->{state_message} = 'Software '.$entry.' version '.$node->{$what}->{$entry}.' on node '.$node_uuid.' is not supported. Supported are minimum version '.$SOFTWARE_VERSION->{$what}->{$entry}->{min}.' and maximum version '.$SOFTWARE_VERSION->{$what}->{$entry}->{max};
                                $self->{cache} = {};
                                $self->{lock} = 0;
                                Lim::WARN and $self->{logger}->warn($self->{uuid}, ': FAILURE: ', $self->{state_message});
                                return;
                            }
                        }
                    }
                }
                
                Lim::DEBUG and $self->{logger}->debug($self->{uuid}, ': Version information correct and supported');
                $self->{cache}->{version} = $result;
                $self->Timer(0);
            }
            
            $self->{lock} = 0;
        });
        $self->Timer;
        return;
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

            Lim::DEBUG and $self->{logger}->debug($self->{uuid}, ': Setting up HSM ', $hsm->{uuid});
            next;

            $self->{lock} = 1;
            $self->{node_watcher}->SetupHSM($hsm->{xml}, sub {
                my ($result) = @_;
                
                unless (defined $self) {
                    return;
                }
                
                # TODO
                
                $self->{lock} = 0;
            });
            $self->Timer;
            return;
        }
        
        Lim::DEBUG and $self->{logger}->debug($self->{uuid}, ': All HSMs setup');
        $self->{cache}->{hsms_setup} = 1;
    }
    
    #
    # Configure/Initiate/Verify Policy
    #
    
    #
    #
    #
    $self->{state} = CLUSTER_STATE_OPERATIONAL;
    
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
        unless (exists $zone->{content}) {
            Lim::DEBUG and $self->{logger}->debug($self->{uuid}, ': Fetching zone content for zone ', $zone->{uuid});
            $zone->{lock} = 1;
            $zone->{input}->Fetch(sub {
                my ($content) = @_;
                
                unless (defined $self) {
                    return;
                }
                
                if (defined $content) {
                    Lim::DEBUG and $self->{logger}->debug($self->{uuid}, ': Zone content for zone ', $zone->{uuid}, ' fetched');
                    $zone->{content} = $content;
                    $zone->{content_timestamp} = AnyEvent->now;
                }
                
                $zone->{lock} = 0;
            });
            next;
        }
        
        #
        # Configure/Initiate/Verify Zone
        #

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
    
    $self->{logger}->debug($self->{uuid}, ': Run() done');

    $self->Timer;
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
