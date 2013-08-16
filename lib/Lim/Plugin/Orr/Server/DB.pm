package Lim::Plugin::Orr::Server::DB;

use common::sense;

use Carp;
use Scalar::Util qw(weaken blessed);
use UUID ();

use Lim::Plugin::Orr ();

=encoding utf8

=head1 NAME

Lim::Plugin::Orr::Server::DB - Database functions for the server class of the
OpenDNSSEC Redundancy Robot Lim plugin

=head1 VERSION

See L<Lim::Plugin::Orr> for version.

=cut

our $VERSION = $Lim::Plugin::Orr::VERSION;

=head1 SYNOPSIS

  use base qw(Lim::Plugin::Orr::Server::DB);

=head1 METHODS

These methods handles the database for OpenDNSSEC Redundancy Robot.

=over 4

=item dbSetup

Setup the database, create all the tables if they dont exist or upgrade an
existing database if there is a new version.

=cut

sub dbSetup {
    my ($self, $dbh, $cb) = @_;
    my $real_self = $self;
    weaken($self);
    
    unless (ref($cb) eq 'CODE') {
        confess '$cb is not CODE';
    }
    
    unless (blessed $dbh and $dbh->isa('AnyEvent::DBI')) {
        $@ = '$dbh is not AnyEvent::DBI';
        $cb->();
        return;
    }

    $dbh->exec('SELECT version FROM version',
        sub {
            my ($dbh, $rows, $rv) = @_;
            
            unless (defined $self) {
                $cb->();
                undef $cb;
                return;
            }
            
            unless ($rv and ref($rows) eq 'ARRAY') {
                $self->dbCreate($dbh, $cb);
                undef $cb;
                return;
            }

            unless (scalar @$rows == 1 and ref($rows->[0]) eq 'ARRAY' and scalar @{$rows->[0]} == 1) {
                $@ = 'Database schema error, no version information.';
                $cb->();
                undef $cb;
                return;
            }

            if ($rows->[0]->[0] gt $VERSION) {
                $@ = 'Database schema error, version is larger then plugin.';
                $cb->();
                undef $cb;
                return;
            }
            
            if ($rows->[0]->[0] lt $VERSION) {
                $self->dbUpgrade($dbh, $cb, $rows->[0]->[0]);
                undef $cb;
                return;
            }

            $cb->(1);
            undef $cb;
            return;
        });
}

=item dbCreate

=cut

our @__tables = (
    'CREATE TABLE version ( version varchar(16) not null, primary key (version) )'
);

our @__data = (
    [ 'INSERT INTO version ( version ) VALUES ( ? )', $VERSION ]
);

sub dbCreate {
    my ($self, $dbh, $cb) = @_;
    my $real_self = $self;
    weaken($self);

    my @tables = @__tables;
    my @data = @__data;
    my $code; $code = sub {
        my ($dbh) = @_;
        
        unless (defined $self) {
            $cb->();
            undef $cb;
            return;
        }
        
        if (defined (my $table = shift(@tables))) {
            $dbh->exec($table,
                sub {
                    my ($dbh, undef, $rv) = @_;
                    
                    unless (defined $self) {
                        $cb->();
                        undef $cb;
                        return;
                    }
                    
                    unless ($rv) {
                        $@ = 'Database creation failed, unable to create table: '.$@;
                        $cb->();
                        undef $cb;
                        return;
                    }
                    
                    $code->($dbh);
                });
            return;
        }
        
        if (defined (my $data = shift(@data))) {
            $dbh->exec(@$data,
                sub {
                    my ($dbh, undef, $rv) = @_;
                    
                    unless (defined $self) {
                        $cb->();
                        undef $cb;
                        return;
                    }
                    
                    unless ($rv) {
                        $@ = 'Database creation failed, unable to populate table: '.$@;
                        $cb->();
                        undef $cb;
                        return;
                    }
                    
                    $code->($dbh);
                });
            return;
        }
        
        $cb->(1);
        undef $cb;
        return;
    };
    $code->($dbh);
}

=item dbUpgrade

=cut

sub dbUpgrade {
    my ($self, $dbh, $cb) = @_;
    my $real_self = $self;
    weaken($self);
    
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
