package Lim::Plugin::Orr::Server::DB;

use common::sense;

use Carp;
use Scalar::Util qw(weaken blessed);
use UUID ();
use Log::Log4perl ();
use JSON::XS ();

use Lim::Util::DBI ();

use Lim::Plugin::Orr ();

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server::DB - Database layer for the OpenDNSSEC Redundancy
Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;

=head1 SYNOPSIS

  use Lim::Plugin::Orr::Server::DB;
  
  my $db = Lim::Plugin::Orr::Server::DB->new(...);

=head1 DESCRIPTION

This is the database layer for the OpenDNSSEC Redundancy Robot.

=head1 METHODS

These methods handles the database for OpenDNSSEC Redundancy Robot.

=over 4

=item $db = Lim::Plugin::Orr::Server::DB->new(...);

Create a new Database object for the OpenDNSSEC Redundancy Robot.

=over 4

=item dns

=item user

=item password

=item on_connect

=back

=cut

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my %args = ( @_ );
    my $self = {
        logger => Log::Log4perl->get_logger
    };
    bless $self, $class;
    my $real_self = $self;
    weaken($self);

    unless (defined $args{dsn}) {
        confess __PACKAGE__, ': Missing dsn';
    }
    unless (defined $args{user}) {
        confess __PACKAGE__, ': Missing user';
    }
    unless (defined $args{password}) {
        confess __PACKAGE__, ': Missing password';
    }
    unless (ref($args{on_connect}) eq 'CODE') {
        confess __PACKAGE__, ': on_connect is not CODE';
    }
    
    $self->{dsn} = $args{dsn};
    $self->{user} = $args{user};
    $self->{password} = $args{password};
    my $dbh; $dbh = $self->dbh(sub {
        my (undef, $success) = @_;
        
        unless (defined $self and $success) {
            $args{on_connect}->();
            undef $dbh;
            return;
        }
        
        $self->Setup($dbh, sub {
            unless (defined $self) {
                undef $dbh;
                return;
            }
            
            $args{on_connect}->(@_);
            undef $dbh;
        });
    });

    Lim::OBJ_DEBUG and $self->{logger}->debug('new ', __PACKAGE__, ' ', $self);
    $real_self;
}

sub DESTROY {
    my ($self) = @_;
    Lim::OBJ_DEBUG and $self->{logger}->debug('destroy ', __PACKAGE__, ' ', $self);
    
    delete $self->{dbh};
}

=item dbh

=cut

sub dbh {
    my ($self, $on_connect, $on_error) = @_;
    
    unless (ref($on_connect) eq 'CODE') {
        confess __PACKAGE__, ': Missing on_connect';
    }
    if (defined $on_error and ref($on_error) ne 'CODE') {
        confess __PACKAGE__, ': on_error is not CODE';
    }
    
    my $dbh; $dbh = Lim::Util::DBI->new(
        $self->{dsn},
        $self->{user},
        $self->{password},
        RaiseError => 0,
        PrintError => 0,
        mysql_auto_reconnect => 0,
        mysql_enable_utf8 => 1,
        sqlite_unicode => 1,
        on_error => defined $on_error ? $on_error : sub {},
        on_connect => $on_connect
    );

    Lim::DEBUG and $self->{logger}->debug('new dbh ', $dbh);
    
    return $dbh;
}

=item Setup

Setup the database, create all the tables if they dont exist or upgrade an
existing database if there is a new version.

=cut

sub Setup {
    my ($self, $dbh, $cb) = @_;
    weaken($self);
    
    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    unless (blessed $dbh and $dbh->isa('Lim::Util::DBI')) {
        $@ = '$dbh is not Lim::Util::DBI';
        $cb->();
        return;
    }

    Lim::DEBUG and $self->{logger}->debug('Setting up database');
    
    undef $@;
    $dbh->execute('SELECT version FROM version', sub {
        my ($dbh, $rows, $rv) = @_;
        
        unless (defined $self) {
            $cb->();
            return;
        }
        
        unless ($rv and ref($rows) eq 'ARRAY') {
            Lim::DEBUG and $self->{logger}->debug('No version found, creating database');
            $self->Create($dbh, $cb);
            return;
        }

        unless (scalar @$rows == 1 and ref($rows->[0]) eq 'ARRAY' and scalar @{$rows->[0]} == 1) {
            $@ = 'Database schema error, no version information.';
            $cb->();
            return;
        }

        if ($rows->[0]->[0] gt $VERSION) {
            $@ = 'Database schema error, version is larger then plugin.';
            $cb->();
            return;
        }
        
        if ($rows->[0]->[0] lt $VERSION) {
            Lim::DEBUG and $self->{logger}->debug('Database version ', $rows->[0]->[0], ' is less then ', $VERSION, ', upgrading');
            $self->Upgrade($dbh, $cb, $rows->[0]->[0]);
            return;
        }

        Lim::DEBUG and $self->{logger}->debug('Database is current version ', $VERSION);
        $cb->(1);
        return;
    });
}

=item Create

=cut

our @__tables = (
'CREATE TABLE version (
  version varchar(16) not null,
  
  primary key (version)
)',
'CREATE TABLE nodes (
  node_uuid varchar(36) not null,
  
  node_uri varchar(255) not null,
  node_mode varchar(16) not null,

  primary key (node_uuid)
)',
'CREATE TABLE zones (
  zone_uuid varchar(36) not null,
  
  zone_name varchar(255) not null,
  zone_input_type varchar(64) not null,
  zone_input_data text not null,
  
  primary key (zone_uuid),
  unique (zone_name)
)',
'CREATE TABLE clusters (
  cluster_uuid varchar(36) not null,
  
  cluster_mode varchar(16) not null,
  
  primary key (cluster_uuid)
)',
'CREATE TABLE cluster_node (
  cluster_uuid varchar(36) not null,
  node_uuid varchar(36) not null,
  
  primary key (cluster_uuid, node_uuid)
)',
'CREATE INDEX node_uuid_index ON cluster_node (node_uuid)',
'CREATE TABLE cluster_zone (
  cluster_uuid varchar(36) not null,
  zone_uuid varchar(36) not null,
  
  primary key (cluster_uuid, zone_uuid),
  unique (zone_uuid)
)',
'CREATE TABLE hsms (
  hsm_uuid varchar(36) not null,

  hsm_data text not null,

  primary key (hsm_uuid)
)',
'CREATE TABLE cluster_hsm (
  cluster_uuid varchar(36) not null,
  hsm_uuid varchar(36) not null,
  
  primary key (cluster_uuid, hsm_uuid)
)',
'CREATE TABLE policies (
  policy_uuid varchar(36) not null,

  policy_data text not null,

  primary key (policy_uuid)
)',
'CREATE TABLE cluster_policy (
  cluster_uuid varchar(36) not null,
  policy_uuid varchar(36) not null,
  
  primary key (cluster_uuid)
)'
);

sub __uuid {
    my ($uuid, $string);
    UUID::generate($uuid);
    UUID::unparse($uuid, $string);
    return $string;
}

our @__data = (
    [ 'INSERT INTO nodes ( node_uuid, node_uri, node_mode ) VALUES ( ?, ?, ? )', __uuid, 'http://blim:5353', 'PRIMARY' ],
    [ 'INSERT INTO nodes ( node_uuid, node_uri, node_mode ) VALUES ( ?, ?, ? )', __uuid, 'http://clim:5353', 'SECONDARY' ],
    [ 'INSERT INTO zones ( zone_uuid, zone_name, zone_input_type, zone_input_data ) VALUES ( ?, ?, "Lim::Plugin::DNS", ? )', __uuid, 'example.com', JSON::XS->new->ascii->encode({host => 'alim', port => 5353, software => 'BIND'}) ],
    [ 'INSERT INTO clusters ( cluster_uuid, cluster_mode ) VALUES ( ?, ? )', __uuid, 'BACKUP' ],
    [ 'INSERT INTO cluster_node SELECT cluster_uuid, node_uuid FROM clusters, nodes' ],
    [ 'INSERT INTO cluster_zone SELECT cluster_uuid, zone_uuid FROM clusters, zones' ],
    [ 'INSERT INTO version ( version ) VALUES ( ? )', $VERSION ],
    [ 'INSERT INTO hsms VALUES ( ?, ? )',
        __uuid,
        JSON::XS->new->ascii->encode({
            name => 'SoftHSM',
            module => '/usr/lib/softhsm/libsofthsm.so',
            token_label => 'OpenDNSSEC',
            pin => '1234',
            skip_public_key => 1
        })
    ],
    [ 'INSERT INTO cluster_hsm SELECT cluster_uuid, hsm_uuid FROM clusters, hsms' ],
    [ 'INSERT INTO policies VALUES ( ?, ? )',
        __uuid,
        JSON::XS->new->ascii->encode({
            name => 'orr-default',
            description => 'The default policy for Orr',
            signatures => {
                resign => 'PT2H',
                refresh => 'P3D',
                validity => {
                    default => 'P7D',
                    denial => 'P7D'
                },
                jitter => 'PT12H',
                inception_offset => 'PT3600S'
            },
            denial => {
                nsec3 => {
                    resalt => 'P100D',
                    hash => {
                        algorithm => 1,
                        iterations => 5,
                        salt => {
                            length => 8
                        }
                    }
                }
            },
            keys => {
                ttl => 'PT3600S',
                retire_safety => 'PT3600S',
                publish_safety => 'PT3600S',
                purge => 'P14D',
                ksk => {
                    algorithm => {
                        value => 8,
                        length => 2048
                    },
                    lifetime => 'P1Y',
                    repository => 'SoftHSM',
                    manual_rollover => 1
                },
                zsk => {
                    algorithm => {
                        value => 8,
                        length => 1024
                    },
                    lifetime => 'P1Y',
                    repository => 'SoftHSM',
                    manual_rollover => 1
                }
            },
            zone => {
                propagation_delay => 'PT43200S',
                soa => {
                    ttl => 'PT3600S',
                    minimum => 'PT3600S',
                    serial => 'datacounter'
                }
            },
            parent => {
                propagation_delay => 'PT9999S',
                ds => {
                    ttl => 'PT3600S'
                },
                soa => {
                    ttl => 'PT172800S',
                    minimum => 'PT10800S'
                }
            },
            audit => 1
        })
    ],
    [ 'INSERT INTO cluster_policy SELECT cluster_uuid, policy_uuid FROM clusters, policies' ],
);

sub Create {
    my ($self, $dbh, $cb) = @_;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    unless (blessed $dbh and $dbh->isa('Lim::Util::DBI')) {
        $@ = '$dbh is not Lim::Util::DBI';
        $cb->();
        return;
    }

    undef $@;
    my @tables = @__tables;
    my @data = @__data;
    my $transaction = 0;
    my $code; $code = sub {
        my ($dbh) = @_;
        
        unless (defined $self) {
            $cb->();
            return;
        }
        
        if (defined (my $table = shift(@tables))) {
            $dbh->execute($table, sub {
                my ($dbh, undef, $rv) = @_;
                
                unless (defined $self) {
                    $cb->();
                    return;
                }
                
                unless ($rv) {
                    Lim::DEBUG and $self->{logger}->debug($table);
                    $@ = 'Database creation failed, unable to create table: '.$@;
                    $cb->();
                    return;
                }
                
                $code->($dbh);
            });
            return;
        }
        
        unless ($transaction) {
            $dbh->begin_work(sub {
                my ($dbh, $rc) = @_;
                
                unless (defined $self) {
                    $cb->();
                    return;
                }
                
                unless ($rc) {
                    $@ = 'Database creation failed, unable to start transaction: '.$@;
                    $cb->();
                    return;
                }
                
                $transaction = 1;
                $code->($dbh);
            });
            return;
        }
        
        if (defined (my $data = shift(@data))) {
            $dbh->execute(@$data, sub {
                my ($dbh, undef, $rv) = @_;
                
                unless (defined $self) {
                    $cb->();
                    return;
                }
                
                unless ($rv) {
                    Lim::DEBUG and $self->{logger}->debug(join(' ', @$data));
                    $@ = 'Database creation failed, unable to populate table: '.$@;
                    $cb->();
                    return;
                }
                
                $code->($dbh);
            });
            return;
        }

        $dbh->commit(sub {
            my ($dbh, $rc) = @_;
            
            unless (defined $self) {
                $cb->();
                return;
            }
            
            unless ($rc) {
                $@ = 'Database creation failed, unable to commit transaction: '.$@;
                $cb->();
                return;
            }
            
            Lim::DEBUG and $self->{logger}->debug('Database created');
            $cb->(1);
        });
        undef $code;
        return;
    };
    $code->($dbh);
}

=item Upgrade

=cut

sub Upgrade {
    my ($self, $dbh, $cb) = @_;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    unless (blessed $dbh and $dbh->isa('Lim::Util::DBI')) {
        $@ = '$dbh is not Lim::Util::DBI';
        $cb->();
        return;
    }
    
    undef $@;
    $cb->(1);
}

=item NodeList

=cut

sub NodeList {
    my ($self, $cb) = @_;
    weaken($self);
    
    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    undef $@;
    my $dbh; $dbh = $self->dbh(sub {
        my (undef, $success) = @_;
        
        unless (defined $self and $success) {
            $@ = 'Database error'; # TODO better error
            $cb->();
            undef $dbh;
            return;
        }
        
        $dbh->execute('SELECT node_uuid, node_uri, node_mode FROM nodes', sub {
            my (undef, $rows, $rv) = @_;
            
            unless (defined $self and $rv and ref($rows) eq 'ARRAY' and scalar @$rows) {
                $@ = 'Database error'; # TODO better error
                $cb->();
                undef $dbh;
                return;
            }
            
            $cb->(map {
                if (ref($_) eq 'ARRAY') {
                    {
                        uuid => $_->[0],
                        uri => $_->[1],
                        mode => $_->[2]
                    };
                } else {
                    $@ = 'Database error'; # TODO better error
                    $cb->();
                    undef $dbh;
                    return;
                }
            } @$rows);
            undef $dbh;
        });
    });
}

=item ZoneList

=cut

sub ZoneList {
    my ($self, $cb) = @_;
    weaken($self);
    
    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    undef $@;
    my $dbh; $dbh = $self->dbh(sub {
        my (undef, $success) = @_;
        
        unless (defined $self and $success) {
            $@ = 'Database error'; # TODO better error
            $cb->();
            undef $dbh;
            return;
        }
        
        $dbh->execute('SELECT zone_uuid, zone_name FROM zones', sub {
            my (undef, $rows, $rv) = @_;
            
            unless (defined $self and $rv and ref($rows) eq 'ARRAY' and scalar @$rows) {
                $@ = 'Database error'; # TODO better error
                $cb->();
                undef $dbh;
                return;
            }
            
            $cb->(map {
                if (ref($_) eq 'ARRAY') {
                    {
                        uuid => $_->[0],
                        name => $_->[1]
                    };
                } else {
                    $@ = 'Database error'; # TODO better error
                    $cb->();
                    undef $dbh;
                    return;
                }
            } @$rows);
            undef $dbh;
        });
    });
}

=item ClusterList

=cut

sub ClusterList {
    my ($self, $cb) = @_;
    weaken($self);
    
    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    undef $@;
    my $dbh; $dbh = $self->dbh(sub {
        my (undef, $success) = @_;
        
        unless (defined $self and $success) {
            $@ = 'Database error'; # TODO better error
            $cb->();
            undef $dbh;
            return;
        }
        
        $dbh->execute('SELECT cluster_uuid, cluster_mode FROM clusters', sub {
            my (undef, $rows, $rv) = @_;
            
            unless (defined $self and $rv and ref($rows) eq 'ARRAY' and scalar @$rows) {
                $@ = 'Database error'; # TODO better error
                $cb->();
                undef $dbh;
                return;
            }
            
            $cb->(map {
                if (ref($_) eq 'ARRAY') {
                    {
                        uuid => $_->[0],
                        mode => $_->[1]
                    };
                } else {
                    $@ = 'Database error'; # TODO better error
                    $cb->();
                    undef $dbh;
                    return;
                }
            } @$rows);
            undef $dbh;
        });
    });
}

=item ClusterNodes

=cut

sub ClusterNodes {
    my ($self, $cluster_uuid, $cb) = @_;
    weaken($self);
    
    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    undef $@;
    my $dbh; $dbh = $self->dbh(sub {
        my (undef, $success) = @_;
        
        unless (defined $self and $success) {
            $@ = 'Database error'; # TODO better error
            $cb->();
            undef $dbh;
            return;
        }
        
        $dbh->execute('SELECT n.node_uuid, n.node_uri, n.node_mode FROM cluster_node cn INNER JOIN nodes n ON n.node_uuid = cn.node_uuid WHERE cn.cluster_uuid = ?', $cluster_uuid, sub {
            my (undef, $rows, $rv) = @_;
            
            unless (defined $self and $rv and ref($rows) eq 'ARRAY' and scalar @$rows) {
                $@ = 'Database error'; # TODO better error
                $cb->();
                undef $dbh;
                return;
            }
            
            $cb->(map {
                if (ref($_) eq 'ARRAY') {
                    {
                        uuid => $_->[0],
                        uri => $_->[1],
                        mode => $_->[2]
                    };
                } else {
                    $@ = 'Database error'; # TODO better error
                    $cb->();
                    undef $dbh;
                    return;
                }
            } @$rows);
            undef $dbh;
        });
    });
}

=item ClusterZones

=cut

sub ClusterZones {
    my ($self, $cluster_uuid, $cb) = @_;
    weaken($self);
    
    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    undef $@;
    my $dbh; $dbh = $self->dbh(sub {
        my (undef, $success) = @_;
        
        unless (defined $self and $success) {
            $@ = 'Database error'; # TODO better error
            $cb->();
            undef $dbh;
            return;
        }
        
        $dbh->execute('SELECT z.zone_uuid, z.zone_name FROM cluster_zone cz INNER JOIN zones z ON z.zone_uuid = cz.zone_uuid WHERE cz.cluster_uuid = ?', $cluster_uuid, sub {
            my (undef, $rows, $rv) = @_;
            
            unless (defined $self and $rv and ref($rows) eq 'ARRAY' and scalar @$rows) {
                $@ = 'Database error'; # TODO better error
                $cb->();
                undef $dbh;
                return;
            }
            
            $cb->(map {
                if (ref($_) eq 'ARRAY') {
                    {
                        uuid => $_->[0],
                        name => $_->[1]
                    };
                } else {
                    $@ = 'Database error'; # TODO better error
                    $cb->();
                    undef $dbh;
                    return;
                }
            } @$rows);
            undef $dbh;
        });
    });
}

=item ClusterConfig

Returns an array with all cluster configuration suitible for feeding the Cluster
Manager with during start up.

Object example in the array:

{
    uuid => 'string',
    mode => 'string',
    policy => {
        uuid => 'string',
        data => 'string'
    },
    hsms => [
        {
            uuid => 'string',
            data => 'string'
        }
    ],
    nodes => [
        {
            uuid => 'string',
            ...
        }
    ],
    zones => [
        {
            uuid => 'string',
            ...
        }
    ]
}

=cut

sub ClusterConfig {
    my ($self, $cb) = @_;
    
    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    undef $@;
    my $dbh; $dbh = $self->dbh(sub {
        my (undef, $success) = @_;
        
        unless (defined $self and $success) {
            $@ = 'Database error'; # TODO better error
            $cb->();
            undef $dbh;
            return;
        }

        $dbh->execute('SELECT cluster_uuid, cluster_mode FROM clusters', sub {
            my (undef, $rows, $rv) = @_;
            
            unless (defined $self and $rv and ref($rows) eq 'ARRAY' and scalar @$rows) {
                $@ = 'Database error clusters'; # TODO better error
                $cb->();
                undef $dbh;
                return;
            }

            my %cluster = map {
                if (ref($_) eq 'ARRAY') {
                    $_->[0] => {
                        uuid => $_->[0],
                        mode => $_->[1],
                        nodes => [],
                        zones => []
                    };
                } else {
                    $@ = 'Database error cluster rows'; # TODO better error
                    $cb->();
                    undef $dbh;
                    return;
                }
            } @$rows;
            
            $dbh->execute('SELECT cp.cluster_uuid, p.policy_uuid, p.policy_data
                FROM cluster_policy cp
                INNER JOIN policies p ON p.policy_uuid = cp.policy_uuid', sub
            {
                my (undef, $rows, $rv) = @_;
                
                unless (defined $self and $rv and ref($rows) eq 'ARRAY' and scalar @$rows == 1) {
                    $@ = 'Database error policies'; # TODO better error
                    $cb->();
                    undef $dbh;
                    return;
                }
                
                foreach (@$rows) {
                    unless (ref($_) eq 'ARRAY') {
                        $@ = 'Database error policy row'; # TODO better error
                        $cb->();
                        undef $dbh;
                        return;
                    }
                    
                    $cluster{$_->[0]}->{policy} = {
                        uuid => $_->[1],
                        data => $_->[2]
                    };
                }

                $dbh->execute('SELECT ch.cluster_uuid, h.hsm_uuid, h.hsm_data
                    FROM cluster_hsm ch
                    INNER JOIN hsms h ON h.hsm_uuid = ch.hsm_uuid', sub
                {
                    my (undef, $rows, $rv) = @_;
                    
                    unless (defined $self and $rv and ref($rows) eq 'ARRAY' and scalar @$rows) {
                        $@ = 'Database error hsms'; # TODO better error
                        $cb->();
                        undef $dbh;
                        return;
                    }
                    
                    foreach (@$rows) {
                        unless (ref($_) eq 'ARRAY') {
                            $@ = 'Database error hsm row'; # TODO better error
                            $cb->();
                            undef $dbh;
                            return;
                        }
                        
                        push(@{$cluster{$_->[0]}->{hsms}}, {
                            uuid => $_->[1],
                            data => $_->[2]
                        });
                    }
    
                    $dbh->execute('SELECT cn.cluster_uuid, n.node_uuid, n.node_uri, n.node_mode
                        FROM cluster_node cn
                        INNER JOIN nodes n ON n.node_uuid = cn.node_uuid', sub
                    {
                        my (undef, $rows, $rv) = @_;
                        
                        unless (defined $self and $rv and ref($rows) eq 'ARRAY' and scalar @$rows) {
                            $@ = 'Database error nodes'; # TODO better error
                            $cb->();
                            undef $dbh;
                            return;
                        }
                        
                        foreach (@$rows) {
                            unless (ref($_) eq 'ARRAY') {
                                $@ = 'Database error node row'; # TODO better error
                                $cb->();
                                undef $dbh;
                                return;
                            }
                            
                            push(@{$cluster{$_->[0]}->{nodes}}, {
                                uuid => $_->[1],
                                uri => $_->[2],
                                mode => $_->[3]
                            });
                        }
        
                        $dbh->execute('SELECT cz.cluster_uuid, z.zone_uuid, z.zone_name, z.zone_input_type, z.zone_input_data
                            FROM cluster_zone cz
                            INNER JOIN zones z ON z.zone_uuid = cz.zone_uuid', sub
                        {
                            my (undef, $rows, $rv) = @_;
                            
                            unless (defined $self and $rv and ref($rows) eq 'ARRAY' and scalar @$rows) {
                                $@ = 'Database error zones'; # TODO better error
                                $cb->();
                                undef $dbh;
                                return;
                            }
                            
                            foreach (@$rows) {
                                unless (ref($_) eq 'ARRAY') {
                                    $@ = 'Database error zone row'; # TODO better error
                                    $cb->();
                                    undef $dbh;
                                    return;
                                }
                                
                                push(@{$cluster{$_->[0]}->{zones}}, {
                                    uuid => $_->[1],
                                    name => $_->[2],
                                    input_type => $_->[3],
                                    input_data => $_->[4]
                                });
                            }
                            
                            $cb->(values %cluster);
                            undef $dbh;
                        });
                    });
                });
            });
        });
    });
}

=back

=head1 AUTHOR

Jerry Lundström, C<< <lundstrom.jerry at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to L<https://github.com/jelu/lim-plugin-orr/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lim::Plugin::Orr::Server::DB

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

1; # End of Lim::Plugin::Orr::Server::DB
