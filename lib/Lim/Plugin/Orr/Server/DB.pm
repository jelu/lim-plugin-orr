package Lim::Plugin::Orr::Server::DB;

use common::sense;

use Carp;
use Scalar::Util qw(weaken blessed);
use UUID ();
use AnyEvent::DBI ();
use Log::Log4perl ();

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

=item $db = Lim::Plugin::Orr::Server::DB->new(key => value...);

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
    
    my $dbh; $dbh = AnyEvent::DBI->new(
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
    
    unless (blessed $dbh and $dbh->isa('AnyEvent::DBI')) {
        $@ = '$dbh is not AnyEvent::DBI';
        $cb->();
        return;
    }

    Lim::DEBUG and $self->{logger}->debug('Setting up database');
    
    $dbh->exec('SELECT version FROM version', sub {
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
    'CREATE TABLE version ( version varchar(16) not null, primary key (version) )',
    'CREATE TABLE nodes ( node_uuid varchar(36) not null, node_uri varchar(255) not null, primary key (node_uuid) )',
    'CREATE TABLE zones ( zone_uuid varchar(36) not null, zone_filename varchar(255) not null, primary key (zone_uuid), unique (zone_filename) )'
);

sub __uuid {
    my ($uuid, $string);
    UUID::generate($uuid);
    UUID::unparse($uuid, $string);
    return $string;
}

our @__data = (
    [ 'INSERT INTO nodes ( node_uuid, node_uri ) VALUES ( ?, ? )', __uuid, 'http://172.16.21.91:5353' ],
    [ 'INSERT INTO nodes ( node_uuid, node_uri ) VALUES ( ?, ? )', __uuid, 'http://172.16.21.92:5353' ],
    [ 'INSERT INTO version ( version ) VALUES ( ? )', $VERSION ]
);

sub Create {
    my ($self, $dbh, $cb) = @_;
    weaken($self);

    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    unless (blessed $dbh and $dbh->isa('AnyEvent::DBI')) {
        $@ = '$dbh is not AnyEvent::DBI';
        $cb->();
        return;
    }

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
            $dbh->exec($table, sub {
                my ($dbh, undef, $rv) = @_;
                
                unless (defined $self) {
                    $cb->();
                    return;
                }
                
                unless ($rv) {
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
            $dbh->exec(@$data, sub {
                my ($dbh, undef, $rv) = @_;
                
                unless (defined $self) {
                    $cb->();
                    return;
                }
                
                unless ($rv) {
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
    
    unless (blessed $dbh and $dbh->isa('AnyEvent::DBI')) {
        $@ = '$dbh is not AnyEvent::DBI';
        $cb->();
        return;
    }
}

=item NodeList

=cut

sub NodeList {
    my ($self, $cb) = @_;
    weaken($self);
    
    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    my $dbh; $dbh = $self->dbh(sub {
        my (undef, $success) = @_;
        
        unless (defined $self and $success) {
            $cb->();
            undef $dbh;
            return;
        }
        
        $dbh->exec('SELECT node_uuid, node_uri FROM nodes', sub {
            my (undef, $rows, $rv) = @_;
            
            unless (defined $self and $rv and ref($rows) eq 'ARRAY' and scalar @$rows) {
                $cb->();
                undef $dbh;
                return;
            }
            
            $cb->(map {
                if (ref($_) eq 'ARRAY') {
                    {
                        node_uuid => $_->[0],
                        node_uri => $_->[1]
                    };
                } else {
                    $cb->();
                    undef $dbh;
                    return;
                }
            } @$rows);
            undef $dbh;
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

1; # End of Lim::Plugin::Orr::Server::DB
