package Koha::Plugin::Com::OpenFifth::FlywirePayments::Controllers::Callback;

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

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use JSON qw(decode_json encode_json);
use Try::Tiny qw( catch try );

use C4::Context;
use Koha::Account;
use Koha::Account::Lines;
use Koha::Patrons;
use Koha::Plugin::Com::OpenFifth::FlywirePayments;

=head1 NAME

Koha::Plugin::Com::OpenFifth::FlywirePayments::Controllers::Callback

=head1 DESCRIPTION

Controller for handling Flywire Pay-by-Link payment status callbacks.

Flywire sends JSON callbacks at various stages:
- initiated: Payment created
- processed: Funds received/captured
- guaranteed: Funds validated, guaranteed to be sent
- delivered: Funds sent to recipient
- failed: Payment failed
- cancelled: Payment cancelled
- reversed: Payment reversed (refund completed)

=head1 API

=head2 Methods

=head3 process

Process the Flywire payment status callback

=cut

sub process {
    my $c = shift->openapi->valid_input or return;

    my $flywire_plugin = Koha::Plugin::Com::OpenFifth::FlywirePayments->new;
    my $debug = $flywire_plugin->_is_debug_mode;

    $debug and warn "[FlywirePayments] Callback received";

    return try {
        my $callback_body = $c->req->body;

        $debug and warn "[FlywirePayments] Raw callback body: $callback_body";

        # Validate signature if X-Flywire-Digest header is present
        my $received_digest = $c->req->headers->header('X-Flywire-Digest');
        if ($received_digest) {
            unless ($flywire_plugin->validate_callback_signature($callback_body, $received_digest)) {
                warn "[FlywirePayments] Invalid callback signature";
                return $c->render(
                    status => 401,
                    openapi => { error => 'Invalid signature' }
                );
            }
            $debug and warn "[FlywirePayments] Callback signature validated";
        }

        # Parse JSON callback
        my $callback_data;
        try {
            $callback_data = decode_json($callback_body);
        } catch {
            warn "[FlywirePayments] JSON parsing failed: $_";
            return $c->render(
                status => 400,
                openapi => { error => 'Invalid JSON format' }
            );
        };

        my $event_type = $callback_data->{event_type};
        my $event_resource = $callback_data->{event_resource};
        my $data = $callback_data->{data} || {};

        $debug and warn "[FlywirePayments] Event type: $event_type, Resource: $event_resource";

        my $payment_id = $data->{payment_id};
        my $external_reference = $data->{external_reference};  # Our transaction_id
        my $amount_to = $data->{amount_to};
        my $status = $data->{status} || $event_type;

        $debug and warn "[FlywirePayments] Payment ID: " . ($payment_id // 'undef')
           . ", External Reference: " . ($external_reference // 'undef')
           . ", Amount: " . ($amount_to // 'undef')
           . ", Status: " . ($status // 'undef');

        my $transaction;
        if ($external_reference) {
            $transaction = Koha::FlywirePayments::Transactions->find($external_reference);
        }

        unless ($transaction) {
            if ($payment_id) {
                my $transactions = Koha::FlywirePayments::Transactions->search({
                    flywire_reference => $payment_id
                });
                $transaction = $transactions->next if $transactions->count > 0;
            }
        }

        unless ($transaction) {
            warn "[FlywirePayments] Transaction not found for external_reference: "
               . ($external_reference // 'undef') . ", payment_id: " . ($payment_id // 'undef');
            return $c->render(
                status => 404,
                openapi => { error => 'Transaction not found' }
            );
        }

        $debug and warn "[FlywirePayments] Found transaction: " . $transaction->transaction_id;

        # Update transaction with callback data
        $transaction->status($status);
        $transaction->flywire_reference($payment_id) if $payment_id;
        $transaction->callback_data($callback_body);
        $transaction->store();

        # Process based on event type
        if ($event_type eq 'guaranteed') {
            if ($transaction->accountline_id) {
                $debug and warn "[FlywirePayments] Payment already applied for transaction " . $transaction->transaction_id . " - skipping";
            } else {
                $debug and warn "[FlywirePayments] Processing GUARANTEED callback - applying payment";
                $c->_apply_payment($transaction, $data, $flywire_plugin);
            }
        }
        elsif ($event_type eq 'delivered') {
            $debug and warn "[FlywirePayments] Processing DELIVERED callback";
            # Payment already applied on guaranteed, just log
            $c->_log_delivered($transaction, $data, $flywire_plugin);
        }
        elsif ($event_type eq 'cancelled' || $event_type eq 'failed') {
            $debug and warn "[FlywirePayments] Processing $event_type callback";
            # Payment cancelled or failed - update status only
            $transaction->status($event_type);
            $transaction->store();
        }
        elsif ($event_type eq 'reversed') {
            $debug and warn "[FlywirePayments] Processing REVERSED callback - payment refunded";
            # TODO: Handle refund if needed
            $transaction->status('reversed');
            $transaction->store();
        }
        else {
            $debug and warn "[FlywirePayments] Ignoring event type: $event_type";
        }

        # Return success acknowledgment
        return $c->render(
            status => 200,
            openapi => {
                success => JSON::true,
                message => "Callback processed",
                transaction_id => $transaction->transaction_id,
                status => $transaction->status
            }
        );

    } catch {
        warn "[FlywirePayments] Exception caught: $_";
        $c->unhandled_exception($_);
    };
}

=head2 Helper Methods

=head3 _apply_payment

Apply payment to patron account when guaranteed callback is received

=cut

sub _apply_payment {
    my ($c, $transaction, $callback_data, $flywire_plugin) = @_;

    my $debug = $flywire_plugin->_is_debug_mode;
    my $borrowernumber = $transaction->borrowernumber;
    my $amount_pence = $callback_data->{amount_to} || $transaction->amount;
    my $amount_decimal = $amount_pence / 100;

    $debug and warn "[FlywirePayments] Applying payment - borrowernumber: $borrowernumber, amount: $amount_decimal";

    my $patron = Koha::Patrons->find($borrowernumber);
    unless ($patron) {
        warn "[FlywirePayments] Patron $borrowernumber not found";
        return;
    }

    # Set up user environment for Koha::Account operations
    $c->_ensure_user_environment($patron);

    # Get accountlines to pay
    my @accountline_ids = split(',', $transaction->accountline_ids || '');
    $debug and warn "[FlywirePayments] Accountline IDs to pay: " . join(', ', @accountline_ids);

    my $lines_to_pay = Koha::Account::Lines->search(
        { accountlines_id => { 'in' => \@accountline_ids } }
    )->as_list;

    $debug and warn "[FlywirePayments] Found " . scalar(@{$lines_to_pay}) . " accountlines";

    my $patron_account = Koha::Account->new({ patron_id => $borrowernumber });
    my $payment_result = $patron_account->pay({
        amount     => $amount_decimal,
        note       => 'Flywire Payment - ' . ($callback_data->{payment_id} || ''),
        library_id => $patron->branchcode,
        interface  => 'opac',
        lines      => $lines_to_pay,
    });

    # Get payment accountline_id
    my $payment_accountline_id = $flywire_plugin->_version_check('20.05.00')
        ? $payment_result->{payment_id}
        : $payment_result;

    $debug and warn "[FlywirePayments] Payment applied, accountline_id: " . ($payment_accountline_id // 'undef');

    # Update transaction with payment result
    $transaction->accountline_id($payment_accountline_id);
    $transaction->store();

    return $payment_accountline_id;
}

=head3 _log_delivered

Log delivered status (funds sent to recipient)

=cut

sub _log_delivered {
    my ($c, $transaction, $callback_data, $flywire_plugin) = @_;

    my $debug = $flywire_plugin->_is_debug_mode;
    $debug and warn "[FlywirePayments] Payment delivered for transaction: " . $transaction->transaction_id;
    
    # TODO: Generate export file if needed
    # This is where we could trigger any reconciliation/export processes
    
    return 1;
}

=head3 _ensure_user_environment

Set up user environment for payment processing

=cut

sub _ensure_user_environment {
    my ($c, $patron) = @_;
    
    return if C4::Context->userenv;
    
    C4::Context->set_userenv(
        $patron->borrowernumber, $patron->userid,
        $patron->cardnumber, $patron->firstname,
        $patron->surname, $patron->branchcode,
        $patron->flags, undef, undef, undef, undef,
    );
}

1;
