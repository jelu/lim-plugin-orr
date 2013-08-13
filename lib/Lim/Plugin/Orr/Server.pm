package Lim::Plugin::Orr::Server;

use common::sense;

use Scalar::Util qw(weaken);
use UUID ();
use AnyEvent::DBI ();

use Lim::Plugin::Orr ();

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

=back

=head1 METHODS

These methods are called from the Lim framework and should not be used else
where.

Please see L<Lim::Plugin::Orr> for full documentation of calls.

=over 4

=item $server->Init

=cut

sub Init {
    my $self = shift;
    my $real_self = $self;
    weaken($self);
    
    my $dbh; $dbh = AnyEvent::DBI->new(
        @DBI,
        on_error => sub {
            my (undef, undef, undef, $fatal) = @_;
            
            $self->{logger}->error('Init() failed, database error: ', $@);
            undef $dbh;
        },
        on_connect => sub {
            my (undef, $success) = @_;
            
            unless (defined $self) {
                undef $dbh;
                return;
            }
            
            unless ($success) {
                $self->{logger}->error('Init() Unable to connect to database: ', $@);
                undef $dbh;
                return;
            }
            
            $READY = 1;
            undef $dbh;
        });
}

=item $server->Destroy

=cut

sub Destroy {
    $READY = 0;
}

=item $server->ReadNodes

=cut

sub ReadNodes {
    my ($self, $cb) = @_;
    
    unless ($READY) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->CreateNode

=cut

sub CreateNode {
    my ($self, $cb) = @_;
    
    unless ($READY) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadNode

=cut

sub ReadNode {
    my ($self, $cb) = @_;
    
    unless ($READY) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->UpdateNode

=cut

sub UpdateNode {
    my ($self, $cb) = @_;
    
    unless ($READY) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->DeleteNode

=cut

sub DeleteNode {
    my ($self, $cb) = @_;
    
    unless ($READY) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadZones

=cut

sub ReadZones {
    my ($self, $cb) = @_;
    
    unless ($READY) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->CreateZone

=cut

sub CreateZone {
    my ($self, $cb) = @_;
    
    unless ($READY) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->ReadZone

=cut

sub ReadZone {
    my ($self, $cb) = @_;
    
    unless ($READY) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->UpdateZone

=cut

sub UpdateZone {
    my ($self, $cb) = @_;
    
    unless ($READY) {
        $self->Error($cb, 'Orr is not ready or shutting down');
        return;
    }
    
    $self->Error($cb, 'Not implemented');
}

=item $server->DeleteZone

=cut

sub DeleteZone {
    my ($self, $cb) = @_;
    
    unless ($READY) {
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
