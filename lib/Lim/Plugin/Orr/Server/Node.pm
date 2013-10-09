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

sub Unlock {
    my ($self) = @_;
    
    unless ($self->{lock}) {
        confess 'Node is not locked';
    }
    
    $self->{lock} = 0;
    
    unless (exists $self->{timer}) {
        $self->Run;
    }
}

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
            $cb->(1);
        }
        else {
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
            
                                    $cb->($result);
                                }
                                else {
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
                            $cb->($result);
                            $self->Unlock;
                        }
                    }
                    else {
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

                        $cb->($result);
                    }
                    else {
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
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    unless (ref($data) eq 'HASH') {
        confess '$data is not HASH';
    }

    unless ($self->LockOrQueue('SetupHSM', $cb, $data)) {
        return;
    }

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
