package Lim::Plugin::Orr::Server;

use common::sense;

use Scalar::Util qw(weaken);
use UUID ();

use Lim::Plugin::Orr ();
use Lim::Plugin::Orr::Server::DB ();
use Lim::Plugin::Orr::Server::NodeWatcher ();
use Lim::Plugin::Orr::Server::ClusterManager ();

use Lim::Util ();

use base qw(Lim::Component::Server);

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server - Server class for OpenDNSSEC Redundancy Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;

our $READY = 0;

our $DBI_DSN = 'dbi:SQLite:dbname=orr.db';
our $DBI_USER = '';
our $DBI_PASSWORD = '';
our @DBI = (
    $DBI_DSN,
    $DBI_USER,
    $DBI_PASSWORD,
    RaiseError => 0,
    PrintError => 0,
    mysql_auto_reconnect => 0,
    mysql_enable_utf8 => 1,
    sqlite_unicode => 1
);

=head1 SYNOPSIS

  use Lim::Plugin::Orr;

  # Create a Server object
  $server = Lim::Plugin::Orr->Server;

=head1 CONFIGURATION

TODO

=head1 INTERNAL METHODS

These are only internal methods and should not be used externally.

=over 4

=item _Ready

=cut

sub _Ready {
    my ($self) = @_;
    
    $READY = 1;
    $self->{node_watcher}->Timer(0);
    $self->{cluster_manager}->Timer(0);
    Lim::DEBUG and $self->{logger}->debug('Ready!');
}

=item _isReady

=cut

sub _isReady {
    return $READY ? 1 : 0;
}

=back

=head1 METHODS

These methods are called from the Lim framework and should not be used else
where.

Please see L<Lim::Plugin::Orr> for full documentation of calls.

=over 4

=item $server->Init

=cut

sub Init {
    my ($self) = @_;
    weaken($self);

    $self->{node_watcher} = Lim::Plugin::Orr::Server::NodeWatcher->new;
    $self->{cluster_manager} = Lim::Plugin::Orr::Server::ClusterManager->new(
        node_watcher => $self->{node_watcher}
    );
    
    my $db; $db = Lim::Plugin::Orr::Server::DB->new(
        dsn => $DBI_DSN,
        user => $DBI_USER,
        password => $DBI_PASSWORD,
        on_connect => sub {
            my ($success) = @_;
            
            unless (defined $self) {
                return;
            }
            
            if ($success) {
                $self->{db} = $db;
                
                $db->ClusterConfig(sub {
                    unless (defined $self) {
                        return;
                    }
                    
                    # TODO check @_ $@ for error
                    
                    foreach (@_) {
                        unless (ref($_) eq 'HASH') {
                            # TODO error here
                            next;
                        }
                        
                        $self->{cluster_manager}->Add(%$_);
                    }

                    $self->_Ready;
                });
            }
            else {
                $self->{logger}->error('Init() Unable to connect/setup database: ', $@);
            }
        });
}

=item $server->Destroy

=cut

sub Destroy {
    my ($self) = @_;
    
    $READY = 0;
}

=item $server->ReadNodes

=cut

sub ReadNodes {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->CreateNode

=cut

sub CreateNode {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadNode

=cut

sub ReadNode {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->UpdateNode

=cut

sub UpdateNode {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->DeleteNode

=cut

sub DeleteNode {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadZones

=cut

sub ReadZones {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->CreateZone

=cut

sub CreateZone {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadZone

=cut

sub ReadZone {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->UpdateZone

=cut

sub UpdateZone {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->DeleteZone

=cut

sub DeleteZone {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadClusters

=cut

sub ReadClusters {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->CreateCluster

=cut

sub CreateCluster {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadCluster

=cut

sub ReadCluster {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->UpdateCluster

=cut

sub UpdateCluster {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->DeleteCluster

=cut

sub DeleteCluster {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadClusterNodes

=cut

sub ReadClusterNodes {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->CreateClusterNode

=cut

sub CreateClusterNode {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadClusterNode

=cut

sub ReadClusterNode {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->UpdateClusterNode

=cut

sub UpdateClusterNode {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->DeleteClusterNode

=cut

sub DeleteClusterNode {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadClusterZones

=cut

sub ReadClusterZones {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->CreateClusterZone

=cut

sub CreateClusterZone {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadClusterZone

=cut

sub ReadClusterZone {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->UpdateClusterZone

=cut

sub UpdateClusterZone {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->DeleteClusterZone

=cut

sub DeleteClusterZone {
    my ($self, $cb) = @_;
    
    unless ($self->_isReady) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
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

1; # End of Lim::Plugin::Orr::Server
