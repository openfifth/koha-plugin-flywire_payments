package Koha::FlywirePayments::Transactions;

# Copyright 2025 OpenFifth

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use base qw(Koha::Objects);

use Koha::FlywirePayments::Transaction;

=head1 NAME

Koha::FlywirePayments::Transactions - Koha Flywire Pay-by-Link Transactions Object Set class

=head1 DESCRIPTION

Collection of Flywire payment transactions.

=head1 API

=head2 Class Methods

=head3 _type

Returns the DBIx::Class result source name

=cut

sub _type {
    return 'KohaPluginComOpenfifthFlywirepaymentsFlywireTransaction';
}

=head3 object_class

Returns the object class for individual items

=cut

sub object_class {
    return 'Koha::FlywirePayments::Transaction';
}

1;
