use utf8;

package Koha::Schema::Result::KohaPluginComOpenfifthFlywirepaymentsFlywireTransaction;

=head1 NAME

Koha::Schema::Result::KohaPluginComOpenfifthFlywirepaymentsFlywireTransaction

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

=head2 accountline_id

  data_type: 'int'
  extra: {unsigned => 1}
  is_foreign_key: 1
  is_nullable: 1

=head2 updated

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "transaction_id",
  {
    data_type => "int",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "accountline_id",
  {
    data_type => "int",
    extra => { unsigned => 1 },
    is_foreign_key => 1,
    is_nullable => 1,
  },
  "updated",
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

=head2 accountline

Type: belongs_to
Related object: L<Koha::Schema::Result::Accountline>

=cut

__PACKAGE__->belongs_to(
  "accountline",
  "Koha::Schema::Result::Accountline",
  { accountlines_id => "accountline_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "SET NULL",
    on_update     => "CASCADE",
  },
);

sub koha_object_class {
    'Koha::FlywirePayments::Transaction';
}

sub koha_objects_class {
    'Koha::FlywirePayments::Transactions';
}

1;