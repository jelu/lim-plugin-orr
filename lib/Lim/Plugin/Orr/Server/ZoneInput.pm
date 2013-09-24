package Lim::Plugin::Orr::Server::ZoneInput;

use common::sense;

use Carp;
use Scalar::Util qw(weaken);
use Log::Log4perl ();
use JSON::XS ();

use Lim::Plugin::Orr ();

use Lim::Plugin::DNS ();

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server::ZoneInput - Zone input functions for the OpenDNSSEC
Redundancy Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;
our $JSON = JSON::XS->new->ascii->convert_blessed;
our %TYPE = (
    'Lim::Plugin::DNS' => 'LimPluginDNS'
);

=head1 SYNOPSIS

  use Lim::Plugin::Orr::Server::ZoneInput;
  
  my $zone_input = Lim::Plugin::Orr::Server::ZoneInput->new(...);

=head1 DESCRIPTION

This is the zone input layer for the OpenDNSSEC Redundancy Robot that will fetch
zones when creating new zones or updating zones.

=head1 METHODS

=over 4

=item $zone_input = Lim::Plugin::Orr::Server::ZoneInput->new(...);

Create a new ZoneInput object for the OpenDNSSEC Redundancy Robot.

=cut

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my %args = ( @_ );
    my $self = {
        logger => Log::Log4perl->get_logger
    };
    bless $self, $class;

    unless (defined $args{type} and exists $TYPE{$args{type}}) {
        confess __PACKAGE__, ': Missing type or unsupported type';
    }
    unless (defined $args{data}) {
        confess __PACKAGE__, ': Missing data';
    }
    unless (defined $args{zone}) {
        confess __PACKAGE__, ': Missing zone';
    }
    
    $self->{type} = $args{type};
    eval {
        $self->{data} = $JSON->decode($args{data});
    };
    if ($@) {
        confess __PACKAGE__, ': Unable to decode data: ', $@;
    }
    unless ($self->ValidateData) {
        confess __PACKAGE__, ': Unable to validate data: ', $@;
    }
    $self->{zone} = $args{zone};

    Lim::OBJ_DEBUG and $self->{logger}->debug('new ', __PACKAGE__, ' ', $self);
    $self;
}

sub DESTROY {
    my ($self) = @_;
    Lim::OBJ_DEBUG and $self->{logger}->debug('destroy ', __PACKAGE__, ' ', $self);
}

=item ValidateData

=cut

sub ValidateData {
    my ($self) = shift;
    my $validate_data = 'ValidateData_' . $TYPE{$self->{type}};
    
    undef $@;
    
    $self->$validate_data(@_);
}

=item Fetch

=cut

sub Fetch {
    my ($self) = shift;
    my $fetch = 'Fetch_' . $TYPE{$self->{type}};
    
    undef $@;
    
    $self->$fetch(@_);
}

=back

=head1 Lim::Plugin::DNS METHODS

=over 4

=item ValidateData_LimPluginDNS

=cut

sub ValidateData_LimPluginDNS {
    my ($self) = @_;
    
    unless (ref($self->{data}) eq 'HASH') {
        $@ = 'Data is not a hash';
        return;
    }
    
    unless (defined $self->{data}->{host}) {
        $@ = 'Missing host in data';
        return;
    }
    unless (defined $self->{data}->{port}) {
        $@ = 'Missing port in data';
        return;
    }
    
    return 1;
}

=item Fetch_LimPluginDNS

=cut

sub Fetch_LimPluginDNS {
    my ($self, $cb) = @_;
    weaken($self);
    
    unless (ref($cb) eq 'CODE') {
        confess __PACKAGE__, ': cb is not CODE';
    }
    
    my $dns = Lim::Plugin::DNS->Client;
    $dns->ReadZone({
        zone => {
            file => $self->{zone},
            (exists $self->{data}->{software} ? (software => $self->{data}->{software}) : ()),
            as_content => 1
        }
    }, sub {
        my ($call, $response) = @_;
        
        unless (defined $self) {
            undef $dns;
            return;
        }
        
        if ($call->Successful
            and ref($response) eq 'HASH'
            and exists $response->{zone}
            and ref($response->{zone}) eq 'HASH'
            and exists $response->{zone}->{content})
        {
            $cb->($response->{zone}->{content});
        }
        else {
            $cb->();
        }
        undef $dns;
    }, {
        host => $self->{data}->{host},
        port => $self->{data}->{port}
    });
}

=back

=head1 AUTHOR

Jerry Lundström, C<< <lundstrom.jerry at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to L<https://github.com/jelu/lim-plugin-orr/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lim::Plugin::Orr::Server::ZoneInput

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

1; # End of Lim::Plugin::Orr::Server::ZoneInput
