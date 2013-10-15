package Lim::Plugin::Orr::Server::Node;

use common::sense;

use Carp;
use Scalar::Util qw(weaken);
use Log::Log4perl ();

use Lim::Plugin::Orr ();

use Lim::Agent ();
use Lim::Plugin::DNS ();
use Lim::Plugin::OpenDNSSEC ();
use Lim::Plugin::SoftHSM ();

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server::Node - Node functions for the OpenDNSSEC Redundancy
Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;

=head1 SYNOPSIS

  use Lim::Plugin::Orr::Server::Node;
  
  my $node = Lim::Plugin::Orr::Server::Node->new(...);

=head1 DESCRIPTION

This is the node layer for the OpenDNSSEC Redundancy Robot that will make the
actuall calls to the nodes.

=head1 METHODS

These methods does the actuall calls to nodes for the OpenDNSSEC Redundancy
Robot.

=over 4

=item $node = Lim::Plugin::Orr::Server::Node->new(...);

Create a new Node object for the OpenDNSSEC Redundancy Robot.

=cut

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my %args = ( @_ );
    my $self = {
        logger => Log::Log4perl->get_logger,
        last_call => 0,
        queue => [],
        lock => 0
    };
    bless $self, $class;

    unless (defined $args{uri}) {
        confess __PACKAGE__, ': Missing uri';
    }
    
    if ($args{uri} =~ /:\/\/(.*):(\d+)/o) {
        $self->{host} = $1;
        $self->{port} = $2;
    }
    else {
        confess __PACKAGE__, ': Invalid uri';
    }

    Lim::OBJ_DEBUG and $self->{logger}->debug('new ', __PACKAGE__, ' ', $self);
    $self;
}

sub DESTROY {
    my ($self) = @_;
    Lim::OBJ_DEBUG and $self->{logger}->debug('destroy ', __PACKAGE__, ' ', $self);
}

=item Timer

=cut

sub Timer {
    my ($self, $after) = @_;

    if (exists $self->{timer}) {
        return;
    }
    
    weaken($self);
    my $w; $w = $self->{timer} = AnyEvent->timer(
        after => defined $after ? $after : 0,
        cb => sub {
            if (defined $self) {
                delete $self->{timer};
                $self->Run;
            }
            undef $w;
        });
}

=item LockOrQueue

=cut

sub LockOrQueue {
    my $self = shift;

    if ($self->{lock}) {
        Lim::DEBUG and $self->{logger}->debug('Queue work ', $_[0]);
        push(@{$self->{queue}}, [@_]);
        $self->Timer;
        return 0;
    }
    $self->{lock} = 1;
    
    return 1;
}

=item Unlock

=cut

sub Unlock {
    my ($self) = @_;
    
    unless ($self->{lock}) {
        confess 'Node is not locked';
    }
    
    $self->{lock} = 0;
    $self->Run;
}

=item Run

=cut

sub Run {
    my ($self) = @_;
    
    unless (scalar @{$self->{queue}}) {
        return;
    }
    
    if ($self->{lock}) {
        $self->Timer(1);
        return;
    }

    my $work = shift(@{$self->{queue}});
    unless (ref($work) eq 'ARRAY' and scalar @$work) {
        confess 'Work in queue is invalid';
    }

    my $what = shift(@$work);
    unless ($self->can($what)) {
        confess 'Work in queue is invalid';
    }
    
    Lim::DEBUG and $self->{logger}->debug('Poping work ', $what);
    $self->$what(@$work);
}

=item Stop

=cut

sub Stop {
    my ($self) = @_;
    
    $self->{queue} = [];
}

=item Ping

=cut

sub Ping {
    my ($self, $cb) = @_;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }

    unless ($self->LockOrQueue('Ping', $cb)) {
        return;
    }
    
    my $agent = Lim::Agent->Client;
    $agent->ReadVersion(sub {
        my ($call, $response) = @_;
        
        unless (defined $self) {
            undef $agent;
            return;
        }
        
        if ($call->Successful) {
            $self->{last_call} = time;
            undef $@;
            $cb->(1);
        }
        else {
            $@ = $call->Error;
            $cb->();
        }
        $self->Unlock;
        undef $agent;
    }, {
        host => $self->{host},
        port => $self->{port}
    });
}

=item LastCall

=cut

sub LastCall {
    $_[0]->{last_call};
}

=item Versions

=cut

sub Versions {
    my ($self, $cb) = @_;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    unless ($self->LockOrQueue('Versions', $cb)) {
        return;
    }

    my $result = {};
    my $agent = Lim::Agent->Client;
    $agent->ReadPlugins(sub {
        my ($call, $response) = @_;
        
        unless (defined $self) {
            undef $agent;
            return;
        }
        
        if ($call->Successful) {
            $self->{last_call} = time;
            
            if (exists $response->{plugin}) {
                foreach my $plugin (ref($response->{plugin}) eq 'ARRAY' ? @{$response->{plugin}} : $response->{plugin}) {
                    unless ($plugin->{loaded}) {
                        next;
                    }
                    
                    $result->{plugin}->{$plugin->{name}} = $plugin->{version}
                }
            }

            if (exists $result->{plugin}->{SoftHSM}) {
                my $softhsm = Lim::Plugin::SoftHSM->Client;
                $softhsm->ReadVersion(sub {
                    my ($call, $response) = @_;
                
                    unless (defined $self) {
                        undef $softhsm;
                        return;
                    }
                    
                    if ($call->Successful) {
                        $self->{last_call} = time;

                        if (exists $response->{program}) {
                            foreach my $program (ref($response->{program}) eq 'ARRAY' ? @{$response->{program}} : $response->{program}) {
                                $result->{program}->{$program->{name}} = $program->{version}
                            }
                        }

                        if (exists $result->{plugin}->{OpenDNSSEC}) {
                            my $opendnssec = Lim::Plugin::OpenDNSSEC->Client;
                            $opendnssec->ReadVersion(sub {
                                my ($call, $response) = @_;
                            
                                unless (defined $self) {
                                    undef $opendnssec;
                                    return;
                                }
                                
                                if ($call->Successful) {
                                    $self->{last_call} = time;
            
                                    if (exists $response->{program}) {
                                        foreach my $program (ref($response->{program}) eq 'ARRAY' ? @{$response->{program}} : $response->{program}) {
                                            $result->{program}->{$program->{name}} = $program->{version}
                                        }
                                    }
            
                                    undef $@;
                                    $cb->($result);
                                }
                                else {
                                    $@ = $call->Error;
                                    $cb->();
                                }
                                $self->Unlock;
                                undef $opendnssec;
                            }, {
                                host => $self->{host},
                                port => $self->{port}
                            });
                        }
                        else {
                            undef $@;
                            $cb->($result);
                            $self->Unlock;
                        }
                    }
                    else {
                        $@ = $call->Error;
                        $cb->();
                        $self->Unlock;
                    }
                    undef $softhsm;
                }, {
                    host => $self->{host},
                    port => $self->{port}
                });
            }
            elsif (exists $result->{plugin}->{OpenDNSSEC}) {
                my $opendnssec = Lim::Plugin::OpenDNSSEC->Client;
                $opendnssec->ReadVersion(sub {
                    my ($call, $response) = @_;
                
                    unless (defined $self) {
                        undef $opendnssec;
                        return;
                    }
                    
                    if ($call->Successful) {
                        $self->{last_call} = time;

                        if (exists $response->{program}) {
                            foreach my $program (ref($response->{program}) eq 'ARRAY' ? @{$response->{program}} : $response->{program}) {
                                $result->{program}->{$program->{name}} = $program->{version}
                            }
                        }

                        undef $@;
                        $cb->($result);
                    }
                    else {
                        $@ = $call->Error;
                        $cb->();
                    }
                    $self->Unlock;
                    undef $opendnssec;
                }, {
                    host => $self->{host},
                    port => $self->{port}
                });
            }
        }
        else {
            $@ = $call->Error;
            $cb->();
            $self->Unlock;
        }
        undef $agent;
    }, {
        host => $self->{host},
        port => $self->{port}
    });
}

=item SetupHSM

=cut

sub SetupHSM {
    my ($self, $cb, $data) = @_;
    my $json = JSON::XS->new->ascii->canonical;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    eval {
        $data = $json->decode($data);
    };
    if ($@) {
        confess 'unable to decode HSM json data: '.$@;
    }
    unless (ref($data) eq 'HASH') {
        confess 'HSM json data is not HASH';
    }

    unless ($self->LockOrQueue('SetupHSM', $cb, $data)) {
        return;
    }

    my $opendnssec = Lim::Plugin::OpenDNSSEC->Client;
    $opendnssec->ReadRepository({
        repository => {
            name => $data->{name}
        }
    }, sub {
        my ($call, $response) = @_;
        
        unless (defined $self) {
            undef $opendnssec;
            return;
        }
        
        if ($call->Successful) {
            $self->{last_call} = time;
            
            if (exists $response->{repository}) {
                my $repository = ref($response->{repository}) eq 'ARRAY' ? $response->{repository}->[0] : $response->{repository};
                
                my $same = 0;
                eval {
                    $same = $json->encode($response->{repository}) eq $json->encode($data) ? 1 : 0;
                };
                if ($@) {
                    Lim::ERR and $self->{logger}->error('Unable to compare HSM data, JSON error: ', $@);
                    $cb->();
                }
                elsif (!$same) {
                    Lim::DEBUG and $self->{logger}->debug('Repository ', $data->{name}, ' needs updating');
                    $opendnssec->UpdateRepository({
                        repository => $data
                    }, sub {
                        my ($call, $response) = @_;
                        
                        unless (defined $self) {
                            undef $opendnssec;
                            return;
                        }
                        
                        if ($call->Successful) {
                            $self->{last_call} = time;
                            Lim::DEBUG and $self->{logger}->debug('Repository ', $data->{name}, ' updated');
                            undef $@;
                            $cb->(1, 1);
                        }
                        else {
                            $@ = $call->Error;
                            $cb->();
                        }
                        $self->Unlock;
                        undef $opendnssec;
                    }, {
                        host => $self->{host},
                        port => $self->{port}
                    });
                    return;
                }
                
                Lim::DEBUG and $self->{logger}->debug('Repository ', $data->{name}, ' is up to date');
                undef $@;
                $cb->(1);
            }
            else {
                Lim::DEBUG and $self->{logger}->debug('Repository ', $data->{name}, ' not found, creating');
                $opendnssec->CreateRepository({
                    repository => $data
                }, sub {
                    my ($call, $response) = @_;
                    
                    unless (defined $self) {
                        undef $opendnssec;
                        return;
                    }
                    
                    if ($call->Successful) {
                        $self->{last_call} = time;
                        Lim::DEBUG and $self->{logger}->debug('Repository ', $data->{name}, ' created');
                        undef $@;
                        $cb->(1, 1);
                    }
                    else {
                        $@ = $call->Error;
                        $cb->();
                    }
                    $self->Unlock;
                    undef $opendnssec;
                }, {
                    host => $self->{host},
                    port => $self->{port}
                });
                return;
            }
        }
        else {
            $@ = $call->Error;
            $cb->();
        }
        $self->Unlock;
        undef $opendnssec;
    }, {
        host => $self->{host},
        port => $self->{port}
    });
}

=item SetupPolicy

=cut

sub SetupPolicy {
    my ($self, $cb, $data) = @_;
    my $json = JSON::XS->new->ascii->canonical;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    eval {
        $data = $json->decode($data);
    };
    if ($@) {
        confess 'unable to decode Policy json data: '.$@;
    }
    unless (ref($data) eq 'HASH') {
        confess 'Policy json data is not HASH';
    }

    unless ($self->LockOrQueue('SetupPolicy', $cb, $data)) {
        return;
    }

    my $opendnssec = Lim::Plugin::OpenDNSSEC->Client;
    $opendnssec->ReadPolicy({
        policy => {
            name => $data->{name}
        }
    }, sub {
        my ($call, $response) = @_;
        
        unless (defined $self) {
            undef $opendnssec;
            return;
        }
        
        if ($call->Successful) {
            $self->{last_call} = time;
            
            if (exists $response->{policy}) {
                my $policy = ref($response->{policy}) eq 'ARRAY' ? $response->{policy}->[0] : $response->{policy};
                
                my $same = 0;
                eval {
                    $same = $json->encode($response->{policy}) eq $json->encode($data) ? 1 : 0;
                };
                if ($@) {
                    Lim::ERR and $self->{logger}->error('Unable to compare Policy data, JSON error: ', $@);
                    $cb->();
                }
                elsif (!$same) {
                    Lim::DEBUG and $self->{logger}->debug('Policy ', $data->{name}, ' needs updating');
                    $opendnssec->UpdatePolicy({
                        policy => $data
                    }, sub {
                        my ($call, $response) = @_;
                        
                        unless (defined $self) {
                            undef $opendnssec;
                            return;
                        }
                        
                        if ($call->Successful) {
                            $self->{last_call} = time;
                            Lim::DEBUG and $self->{logger}->debug('Policy ', $data->{name}, ' updated');
                            undef $@;
                            $cb->(1, 1);
                        }
                        else {
                            $@ = $call->Error;
                            $cb->();
                        }
                        $self->Unlock;
                        undef $opendnssec;
                    }, {
                        host => $self->{host},
                        port => $self->{port}
                    });
                    return;
                }
                
                Lim::DEBUG and $self->{logger}->debug('Policy ', $data->{name}, ' is up to date');
                undef $@;
                $cb->(1);
            }
            else {
                Lim::DEBUG and $self->{logger}->debug('Policy ', $data->{name}, ' not found, creating');
                $opendnssec->CreatePolicy({
                    policy => $data
                }, sub {
                    my ($call, $response) = @_;
                    
                    unless (defined $self) {
                        undef $opendnssec;
                        return;
                    }
                    
                    if ($call->Successful) {
                        $self->{last_call} = time;
                        Lim::DEBUG and $self->{logger}->debug('Policy ', $data->{name}, ' created');
                        undef $@;
                        $cb->(1, 1);
                    }
                    else {
                        $@ = $call->Error;
                        $cb->();
                    }
                    $self->Unlock;
                    undef $opendnssec;
                }, {
                    host => $self->{host},
                    port => $self->{port}
                });
                return;
            }
        }
        else {
            $@ = $call->Error;
            $cb->();
        }
        $self->Unlock;
        undef $opendnssec;
    }, {
        host => $self->{host},
        port => $self->{port}
    });
}

=item StartOpenDNSSEC

=cut

sub StartOpenDNSSEC {
    my ($self, $cb) = @_;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }

    unless ($self->LockOrQueue('StartOpenDNSSEC', $cb)) {
        return;
    }
    
    my $opendnssec = Lim::Plugin::OpenDNSSEC->Client;
    $opendnssec->UpdateControlStart(sub {
        my ($call, $response) = @_;
        
        unless (defined $self) {
            undef $opendnssec;
            return;
        }
        
        if ($call->Successful) {
            $self->{last_call} = time;
            $cb->(1);
        }
        else {
            $@ = $call->Error;
            $cb->();
        }
        $self->Unlock;
        undef $opendnssec;
    }, {
        host => $self->{host},
        port => $self->{port}
    });
}

=item ReloadOpenDNSSEC

=cut

sub ReloadOpenDNSSEC {
    my ($self, $cb) = @_;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }

    unless ($self->LockOrQueue('ReloadOpenDNSSEC', $cb)) {
        return;
    }
    
    my $opendnssec = Lim::Plugin::OpenDNSSEC->Client;
    $opendnssec->UpdateEnforcerUpdate(sub {
        my ($call, $response) = @_;
        
        unless (defined $self) {
            undef $opendnssec;
            return;
        }
        
        if ($call->Successful) {
            $self->{last_call} = time;
            $cb->(1);
        }
        else {
            $@ = $call->Error;
            $cb->();
        }
        $self->Unlock;
        undef $opendnssec;
    }, {
        host => $self->{host},
        port => $self->{port}
    });
}

=item ZoneAdd

=cut

sub ZoneAdd {
    my ($self, $cb, $name, $content, $policy) = @_;
    my $json = JSON::XS->new->ascii->canonical;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    unless (defined $name) {
        confess '$name is missing';
    }
    unless (defined $content) {
        confess '$content is missing';
    }
    eval {
        $policy = $json->decode($policy);
    };
    if ($@) {
        confess 'unable to decode Policy json data: '.$@;
    }
    unless (ref($policy) eq 'HASH') {
        confess 'Policy json data is not HASH';
    }

    unless ($self->LockOrQueue('ZoneAdd', $cb, $name, $content, $policy)) {
        return;
    }
    
    my $dns = Lim::Plugin::DNS->Client;
    $dns->ReadZones(sub {
        my ($call, $response) = @_;
        
        unless (defined $self) {
            undef $dns;
            return;
        }
        
        if ($call->Successful) {
            $self->{last_call} = time;
            
            undef $@;
            my $exists = 0;
            if (exists $response->{zone}) {
                foreach my $zone (ref($response->{zone}) eq 'ARRAY' ? @{$response->{zone}} : $response->{zone}) {
                    # TODO path should be configurable per node
                    if ($zone->{file} eq '/var/lib/opendnssec/unsigned/'.$name) {
                        unless ($zone->{write}) {
                            $@ = 'Zone exists but is not writable';
                        }
                        $exists = 1;
                    }
                }
            }
            
            unless ($@) {
                if ($exists) {
                    $dns->UpdateZone({
                        zone => {
                            # TODO path should be configurable per node
                            file => '/var/lib/opendnssec/unsigned/'.$name,
                            content => $content
                        }
                    }, sub {
                        my ($call, $response) = @_;
                        
                        unless (defined $self) {
                            undef $dns;
                            return;
                        }
                        
                        if ($call->Successful) {
                            $self->{last_call} = time;
                            $self->ZoneAdd_Enforcer($cb, $name, $policy);
                            undef $dns;
                            return;
                        }
                        else {
                            $@ = $call->Error;
                            $cb->();
                        }
                        $self->Unlock;
                        undef $dns;
                    }, {
                        host => $self->{host},
                        port => $self->{port}
                    });
                    return;
                }
                else {
                    $dns->CreateZone({
                        zone => {
                            # TODO path should be configurable per node
                            file => '/var/lib/opendnssec/unsigned/'.$name,
                            content => $content
                        }
                    }, sub {
                        my ($call, $response) = @_;
                        
                        unless (defined $self) {
                            undef $dns;
                            return;
                        }
                        
                        if ($call->Successful) {
                            $self->{last_call} = time;
                            $self->ZoneAdd_Enforcer($cb, $name, $policy);
                            undef $dns;
                            return;
                        }
                        else {
                            $@ = $call->Error;
                            $cb->();
                        }
                        $self->Unlock;
                        undef $dns;
                    }, {
                        host => $self->{host},
                        port => $self->{port}
                    });
                    return;
                }
            }
            $cb->();
        }
        else {
            $@ = $call->Error;
            $cb->();
        }
        $self->Unlock;
        undef $dns;
    }, {
        host => $self->{host},
        port => $self->{port}
    });
}

=item ZoneAdd_Enforcer

=cut

sub ZoneAdd_Enforcer {
    my ($self, $cb, $name, $policy) = @_;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    unless (defined $name) {
        confess '$name is missing';
    }
    unless (ref($policy) eq 'HASH') {
        confess 'Policy json data is not HASH';
    }
    unless ($self->{lock}) {
        confess 'Called without beign locked';
    }

    my $opendnssec = Lim::Plugin::OpenDNSSEC->Client;
    $opendnssec->ReadEnforcerZoneList(sub {
        my ($call, $response) = @_;
        
        unless (defined $self) {
            undef $opendnssec;
            return;
        }
        
        if ($call->Successful) {
            $self->{last_call} = time;
            
            if (exists $response->{zone}) {
                foreach my $zone (ref($response->{zone}) eq 'ARRAY' ? @{$response->{zone}} : $response->{zone}) {
                    if ($zone->{name} eq $name) {
                        if ($policy->{name} ne $zone->{policy}) {
                            # TODO handle wrong policy
                            
                            $@ = 'Wrong policy';
                            $cb->();
                        }
                        else {
                            $cb->(1);
                        }
                        last;
                    }
                }
            }
            else {
                $opendnssec->CreateEnforcerZone({
                    zone => {
                        name => $name,
                        policy => $policy->{name},
                        # TODO the following paths should be configurable per node
                        signerconf => '/var/lib/opendnssec/signconf/'.$name.'.xml',
                        input => '/var/lib/opendnssec/unsigned/'.$name,
                        output => '/var/lib/opendnssec/signed/'.$name
                    }
                }, sub {
                    my ($call, $response) = @_;
                    
                    unless (defined $self) {
                        undef $opendnssec;
                        return;
                    }
                    
                    if ($call->Successful) {
                        $self->{last_call} = time;
                        
                        # TODO verify that the Signer knows about this zone
                        # and if not we update --all
                        
                        $cb->(1);
                    }
                    else {
                        $@ = $call->Error;
                        $cb->();
                    }
                    $self->Unlock;
                    undef $opendnssec;
                }, {
                    host => $self->{host},
                    port => $self->{port}
                });
                return;
            }
        }
        else {
            $@ = $call->Error;
            $cb->();
        }
        $self->Unlock;
        undef $opendnssec;
    }, {
        host => $self->{host},
        port => $self->{port}
    });
}

=item ZoneRemove

=cut

sub ZoneRemove {
    my ($self, $cb, $name) = @_;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    unless (defined $name) {
        confess '$name is missing';
    }

    unless ($self->LockOrQueue('ZoneRemove', $cb, $name)) {
        return;
    }

    # TODO add logic
    undef $@;
    $cb->();
    $self->Unlock;
}

=back

=head1 AUTHOR

Jerry Lundström, C<< <lundstrom.jerry at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to L<https://github.com/jelu/lim-plugin-orr/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lim::Plugin::Orr::Server::Node

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

1; # End of Lim::Plugin::Orr::Server::Node
