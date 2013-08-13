package Lim::Plugin::Orr;

use common::sense;

use base qw(Lim::Component);

=encoding utf8

=head1 NAME

Lim::Plugin::Orr - Orr management plugin for Lim

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

This plugin lets you manage a Orr installation via Lim.

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
    '...';
}

=item $call_hash_ref = Lim::Plugin::Orr->Calls

Returns a hash reference to the calls that can be made to this plugin, used both
in Server and Client to verify input and output arguments.

See CALLS for list of calls and arguments.

=cut

sub Calls {
    {
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

Copyright 2012-2013 Jerry Lundström.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Lim::Plugin::Orr
