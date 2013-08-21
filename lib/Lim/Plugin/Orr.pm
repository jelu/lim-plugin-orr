package Lim::Plugin::Orr;

use common::sense;

use base qw(Lim::Component);

=encoding utf8

=head1 NAME

Lim::Plugin::Orr - OpenDNSSEC Redundancy Robot

=head1 VERSION

Version 0.10

=cut

our $VERSION = '0.10';

=head1 SYNOPSIS

  use Lim::Plugin::Orr;

  # Create a Server object
  $server = Lim::Plugin::Orr->Server;

  # Create a Client object
  $client = Lim::Plugin::Orr->Client;

  # Create a CLI object
  $cli = Lim::Plugin::Orr->CLI;

=head1 DESCRIPTION

Orr can be configured to manage DNS, OpenDNSSEC and SoftHSM plugins in various
ways to create a redundant DNSSEC system. For example you can configure Orr to
setup a backup/failover system or make a signing cluster that will load balance
the work.

=head1 METHODS

=over 4

=item $plugin_name = Lim::Plugin::Orr->Name

Returns the plugin's name.

=cut

sub Name {
    'Orr';
}

=item $plugin_description = Lim::Plugin::Orr->Description

Returns the plugin's description.

=cut

sub Description {
    'Manage a redundant DNSSEC system with OpenDNSSEC Redundancy Robot';
}

=item $call_hash_ref = Lim::Plugin::Orr->Calls

Returns a hash reference to the calls that can be made to this plugin, used both
in Server and Client to verify input and output arguments.

See CALLS for list of calls and arguments.

=cut

sub Calls {
    {
        #
        # Nodes
        #
        ReadNodes => {
            out => {
                node => {
                    node_uuid => 'string',
                    node_uri => 'string',
                    node_state => 'string'
                }
            }
        },
        CreateNode => {
            in => {
                node => {
                    '' => 'required',
                    node_uri => 'string'
                }
            },
            out => {
                node => {
                    node_uuid => 'string',
                    node_uri => 'string'
                }
            }
        },
        ReadNode => {
            in => {
                node => {
                    '' => 'required',
                    node_uuid => 'string'
                }
            },
            out => {
                node => {
                    node_uuid => 'string',
                    node_uri => 'string',
                    node_state => 'string'
                }
            }
        },
        UpdateNode => {
            in => {
                node => {
                    '' => 'required',
                    node_uuid => 'string',
                    node_uri => 'string optional',
                    node_state => 'string optional'
                }
            }
        },
        DeleteNode => {
            in => {
                node => {
                    '' => 'required',
                    node_uuid => 'string'
                }
            }
        },
        #
        # Zones
        #
        ReadZones => {
            out => {
                zone => {
                    zone_uuid => 'string',
                    zone_filename => 'string',
                    zone_input_type => 'string',
                    zone_input_data => 'string'
                }
            }
        },
        CreateZone => {
            in => {
                zone => {
                    '' => 'required',
                    zone_filename => 'string',
                    zone_input_type => 'string',
                    zone_input_data => 'string'
                }
            },
            out => {
                zone => {
                    zone_uuid => 'string',
                    zone_filename => 'string'
                }
            }
        },
        ReadZone => {
            in => {
                zone => {
                    '' => 'required',
                    zone_uuid => 'string optional',
                    zone_filename => 'string optional'
                }
            },
            out => {
                zone => {
                    zone_uuid => 'string',
                    zone_filename => 'string',
                    zone_input_type => 'string',
                    zone_input_data => 'string'
                }
            }
        },
        UpdateZone => {
            in => {
                zone => {
                    '' => 'required',
                    zone_uuid => 'string',
                    zone_filename => 'string',
                    zone_input_type => 'string',
                    zone_input_data => 'string'
                }
            }
        },
        DeleteZone => {
            in => {
                zone => {
                    '' => 'required',
                    zone_uuid => 'string'
                }
            }
        },
        #
        # Clusters
        #
        ReadClusters => {
            out => {
                cluster => {
                    cluster_uuid => 'string',
                    cluster_mode => 'string'
                }
            }
        },
        CreateCluster => {
            in => {
                cluster => {
                    '' => 'required',
                    cluster_mode => 'string'
                }
            },
            out => {
                cluster => {
                    cluster_uuid => 'string'
                }
            }
        },
        ReadCluster => {
            in => {
                cluster => {
                    '' => 'required',
                    cluster_uuid => 'string'
                }
            },
            out => {
                cluster => {
                    cluster_uuid => 'string',
                    cluster_mode => 'string'
                }
            }
        },
        UpdateCluster => {
            in => {
                cluster => {
                    '' => 'required',
                    cluster_uuid => 'string',
                    cluster_mode => 'string'
                }
            }
        },
        DeleteCluster => {
            in => {
                cluster => {
                    '' => 'required',
                    cluster_uuid => 'string'
                }
            }
        },
        #
        # ClusterNodes
        #
        ReadClusterNodes => {
            in => {
                cluster_node => {
                    cluster_uuid => 'string optional',
                    node_uuid => 'string optional'
                }
            },
            out => {
                cluster_node => {
                    cluster_uuid => 'string',
                    node_uuid => 'string'
                }
            }
        },
        CreateClusterNode => {
            in => {
                cluster_node => {
                    '' => 'required',
                    cluster_uuid => 'string',
                    node_uuid => 'string'
                }
            }
        },
        ReadClusterNode => {
            in => {
                cluster_node => {
                    '' => 'required',
                    cluster_uuid => 'string',
                    node_uuid => 'string'
                }
            },
            out => {
                cluster_node => {
                    cluster_uuid => 'string',
                    node_uuid => 'string'
                }
            }
        },
        # We do not update cluster nodes
        # UpdateClusterNode => {},
        DeleteClusterNode => {
            in => {
                cluster_node => {
                    '' => 'required',
                    cluster_uuid => 'string',
                    node_uuid => 'string'
                }
            }
        },
        #
        # ClusterZones
        #
        ReadClusterZones => {
            in => {
                cluster_zone => {
                    cluster_uuid => 'string optional',
                    zone_uuid => 'string optional'
                }
            },
            out => {
                cluster_zone => {
                    cluster_uuid => 'string',
                    zone_uuid => 'string'
                }
            }
        },
        CreateClusterZone => {
            in => {
                cluster_zone => {
                    '' => 'required',
                    cluster_uuid => 'string',
                    zone_uuid => 'string'
                }
            }
        },
        ReadClusterZone => {
            in => {
                cluster_zone => {
                    '' => 'required',
                    cluster_uuid => 'string',
                    zone_uuid => 'string'
                }
            },
            out => {
                cluster_zone => {
                    cluster_uuid => 'string',
                    zone_uuid => 'string'
                }
            }
        },
        # We do not update cluster zones
        # UpdateClusterZone => {},
        DeleteClusterZone => {
            in => {
                cluster_zone => {
                    '' => 'required',
                    cluster_uuid => 'string',
                    zone_uuid => 'string'
                }
            }
        },
    };
}

=item $command_hash_ref = Lim::Plugin::Orr->Commands

Returns a hash reference to the CLI commands that can be made by this plugin.

See COMMANDS for list of commands and arguments.

=cut

sub Commands {
    {
    };
}

=back

=head1 CALLS

See L<Lim::Component::Client> on how calls and callback functions should be
used.

=over 4

=back

=head1 COMMANDS

=over 4

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

1; # End of Lim::Plugin::Orr
