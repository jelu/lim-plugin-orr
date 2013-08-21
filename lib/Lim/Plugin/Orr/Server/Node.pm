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
        last_call => 0
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

=item Ping

=cut

sub Ping {
    my ($self, $cb) = @_;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
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

1; # End of Lim::Plugin::Orr::Server::Node
