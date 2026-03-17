use utf8;

package Koha::Schema::Result::KohaPluginComOpenfifthFlywirepaymentsFlywireTransaction;

=head1 NAME

Koha::Schema::Result::KohaPluginComOpenfifthFlywirepaymentsFlywireTransaction

=head1 DESCRIPTION

DBIx::Class schema for Flywire Pay-by-Link payment transactions.

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<koha_plugin_com_openfifth_flywirepayments_flywire_transactions>

=cut

__PACKAGE__->table("koha_plugin_com_openfifth_flywirepayments_flywire_transactions");

=head1 ACCESSORS

=head2 transaction_id

  data_type: 'int'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

Primary key, auto-incrementing transaction ID.

=head2 borrowernumber

  data_type: 'int'
  extra: {unsigned => 1}
  is_nullable: 1

The patron who initiated the payment.

=head2 payment_accountline_id

  data_type: 'int'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

The payment accountline created when payment is applied.

=head2 charge_accountline_ids

  data_type: 'text'
  is_nullable: 1

Comma-separated list of charge accountline IDs being paid.

=head2 amount

  data_type: 'int'
  is_nullable: 1

Payment amount in pence (subunits).

=head2 flywire_reference

  data_type: 'varchar'
  size: 255
  is_nullable: 1

Flywire payment reference/ID.

=head2 status

  data_type: 'varchar'
  size: 50
  default_value: 'pending'
  is_nullable: 1

Current status: pending, initiated, processed, guaranteed, delivered, failed, cancelled, reversed.

=head2 updated

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 1

Last update timestamp.

=head2 created

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 1

Creation timestamp.

=cut

__PACKAGE__->add_columns(
  "transaction_id",
  {
    data_type => "int",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "borrowernumber",
  {
    data_type => "int",
    extra => { unsigned => 1 },
    is_nullable => 1,
  },
  "payment_accountline_id",
  {
    data_type => "int",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "charge_accountline_ids",
  {
    data_type => "text",
    is_nullable => 1,
  },
  "amount",
  {
    data_type => "int",
    is_nullable => 1,
  },
  "flywire_reference",
  {
    data_type => "varchar",
    size => 255,
    is_nullable => 1,
  },
  "status",
  {
    data_type => "varchar",
    size => 50,
    default_value => "pending",
    is_nullable => 1,
  },
  "updated",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 1,
  },
  "created",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 1,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</transaction_id>

=back

=cut

__PACKAGE__->set_primary_key("transaction_id");

=head1 RELATIONS

=head2 payment_accountline

Type: belongs_to
Related object: L<Koha::Schema::Result::Accountline>

=cut

__PACKAGE__->belongs_to(
  "payment_accountline",
  "Koha::Schema::Result::Accountline",
  { accountlines_id => "payment_accountline_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "SET NULL",
    on_update     => "CASCADE",
  },
);

=head2 borrower

Type: belongs_to
Related object: L<Koha::Schema::Result::Borrower>

=cut

__PACKAGE__->belongs_to(
  "borrower",
  "Koha::Schema::Result::Borrower",
  { borrowernumber => "borrowernumber" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "SET NULL",
    on_update     => "CASCADE",
  },
);

=head1 KOHA OBJECT METHODS

=head2 koha_object_class

=cut

sub koha_object_class {
    'Koha::FlywirePayments::Transaction';
}

=head2 koha_objects_class

=cut

sub koha_objects_class {
    'Koha::FlywirePayments::Transactions';
}

1;
