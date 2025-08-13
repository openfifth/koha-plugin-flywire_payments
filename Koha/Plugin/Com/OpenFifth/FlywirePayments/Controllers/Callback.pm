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

use XML::LibXML;
use Try::Tiny qw( catch try );

use C4::Context;
use C4::Circulation;
use Koha::Account;
use Koha::Account::Lines;
use Koha::Patrons;
use Koha::Items;
use Koha::Plugin::Com::OpenFifth::FlywirePayments;

=head1 API

=head2 Methods

=head3 process

Process the WPM payment callback

=cut

sub process {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $flywire_plugin = Koha::Plugin::Com::OpenFifth::FlywirePayments->new;
        my $callback_xml = $c->req->body;
        
        my $parsed_request = $c->_parse_payment_request($callback_xml);
        my $patron = Koha::Patrons->find($parsed_request->{borrowernumber});
        
        unless ($patron) {
            return $c->render_resource_not_found("Patron");
        }
        
        $c->_ensure_user_environment($patron);
        
        if ($parsed_request->{payment_succeeded}) {
            $c->_process_successful_payment($parsed_request, $flywire_plugin);
        }
        
        return $c->_build_flywire_acknowledgment($parsed_request->{message_id});
        
    } catch {
        $c->unhandled_exception($_);
    };
}

=head2 Helper Methods

=head3 _parse_payment_request

Parse the incoming Flywire XML request

=cut

sub _parse_payment_request {
    my ($c, $xml_string) = @_;
    
    my $payment_request_xml;
    try {
        $payment_request_xml = XML::LibXML->load_xml(string => $xml_string);
    } catch {
        # For XML parsing errors, we need to return a custom response since
        # Flywire expects XML format, not standard Koha API error format
        $c->render(status => 400, text => 'Invalid XML format', format => 'txt');
        return;
    };

    return {
        borrowernumber => $payment_request_xml->findvalue('/flywire_paymentrequest/customerid'),
        transaction_id => $payment_request_xml->findvalue('/flywire_paymentrequest/transactionreference'),
        payment_succeeded => $payment_request_xml->findvalue('/flywire_paymentrequest/transaction/success') eq '1',
        total_amount => $payment_request_xml->findvalue('/flywire_paymentrequest/transaction/totalpaid'),
        message_id => $payment_request_xml->findvalue('/flywire_paymentrequest/@msgid'),
        xml_document => $payment_request_xml,
    };
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

=head3 _process_successful_payment

Process a successful payment callback

=cut

sub _process_successful_payment {
    my ($c, $request_data, $flywire_plugin) = @_;
    
    my $accountlines_to_pay = $c->_extract_accountlines_from_request($request_data->{xml_document});
    my $payment_processed = $c->_apply_payment_to_account(
        $request_data->{borrowernumber},
        $request_data->{total_amount},
        $accountlines_to_pay,
        $request_data->{transaction_id},
        $flywire_plugin
    );
    
    if ($payment_processed) {
        $c->_process_item_renewals($accountlines_to_pay, $flywire_plugin);
    }
    
    return $payment_processed;
}

=head3 _extract_accountlines_from_request

Extract accountlines to pay from XML request

=cut

sub _extract_accountlines_from_request {
    my ($c, $xml_document) = @_;
    
    my @accountline_ids_to_pay = ();
    my $payment_nodes = $xml_document->findnodes('/flywire_paymentrequest/payments/payment[@paid="1"]');
    
    for my $payment_node ($payment_nodes->get_nodelist) {
        my $accountline_id = $payment_node->findvalue('./@payid');
        push @accountline_ids_to_pay, $accountline_id if $accountline_id;
    }
    
    return \@accountline_ids_to_pay;
}

=head3 _apply_payment_to_account

Apply payment to patron account

=cut

sub _apply_payment_to_account {
    my ($c, $borrowernumber, $payment_amount, $accountline_ids, $transaction_id, $flywire_plugin) = @_;
    
    my $lines_to_pay = Koha::Account::Lines->search(
        { accountlines_id => { 'in' => $accountline_ids } }
    )->as_list;
    
    my $patron_account = Koha::Account->new({ patron_id => $borrowernumber });
    my $payment_result = $patron_account->pay({
        amount => $payment_amount,
        note => 'WPM Payment',
        library_id => Koha::Patrons->find($borrowernumber)->branchcode,
        interface => 'opac',
        lines => $lines_to_pay,
    });
    
    my $payment_accountline_id = $flywire_plugin->_version_check('20.05.00') 
        ? $payment_result->{payment_id} 
        : $payment_result;
    
    $c->_link_payment_to_flywire_transaction($flywire_plugin, $payment_accountline_id, $transaction_id);
    
    return $payment_accountline_id;
}

=head3 _link_payment_to_flywire_transaction

Link payment to Flywire transaction tracking table

=cut

sub _link_payment_to_flywire_transaction {
    my ($c, $flywire_plugin, $payment_id, $transaction_id) = @_;
    
    my $database_handle = C4::Context->dbh;
    my $wmp_transactions_table = $flywire_plugin->get_qualified_table_name('flywire_transactions');
    
    my $update_statement = $database_handle->prepare(
        "UPDATE $wmp_transactions_table SET accountline_id = ? WHERE transaction_id = ?"
    );
    $update_statement->execute($payment_id, $transaction_id);
}

=head3 _process_item_renewals

Process item renewals for paid fines (legacy versions only)

=cut

sub _process_item_renewals {
    my ($c, $paid_lines, $flywire_plugin) = @_;
    
    return if $flywire_plugin->_version_check('20.05.00');
    
    for my $paid_line (@{$paid_lines}) {
        my $item_for_renewal = Koha::Items->find({ itemnumber => $paid_line->itemnumber });
        next unless $item_for_renewal;
        
        if ($c->_item_eligible_for_renewal($paid_line, $flywire_plugin)) {
            $c->_renew_item($paid_line, $flywire_plugin);
        }
    }
}

=head3 _item_eligible_for_renewal

Check if item is eligible for renewal after payment

=cut

sub _item_eligible_for_renewal {
    my ($c, $account_line, $flywire_plugin) = @_;
    
    my $is_overdue_and_returned = $flywire_plugin->_version_check('19.11.00')
        ? ($account_line->debit_type_code eq "OVERDUE" && $account_line->status ne "UNRETURNED")
        : (defined($account_line->accounttype) && $account_line->accounttype eq "FU");
    
    return unless $is_overdue_and_returned;
    
    my $item_details = Koha::Items->find({ itemnumber => $account_line->itemnumber });
    return C4::Circulation::CheckIfIssuedToPatron(
        $account_line->borrowernumber, 
        $item_details->biblionumber
    );
}

=head3 _renew_item

Renew an item after payment

=cut

sub _renew_item {
    my ($c, $account_line, $flywire_plugin) = @_;
    
    my ($renewal_allowed, $renewal_error) = C4::Circulation::CanBookBeRenewed(
        $account_line->borrowernumber, 
        $account_line->itemnumber, 
        0
    );
    
    return unless $renewal_allowed;
    
    if ($flywire_plugin->_version_check('19.11.00')) {
        C4::Circulation::AddRenewal($account_line->borrowernumber, $account_line->itemnumber);
    } else {
        C4::Circulation::_FixOverduesOnReturn($account_line->borrowernumber, $account_line->itemnumber);
        C4::Circulation::AddRenewal($account_line->borrowernumber, $account_line->itemnumber);
    }
}

=head3 _build_flywire_acknowledgment

Build Flywire XML acknowledgment response

=cut

sub _build_flywire_acknowledgment {
    my ($c, $original_message_id) = @_;
    
    my $acknowledgment_xml = XML::LibXML::Document->new('1.0', 'utf-8');
    my $response_root = $acknowledgment_xml->createElement("flywire_messagevalidation");
    $response_root->setAttribute('msgid' => $original_message_id);

    my $validation_element = $acknowledgment_xml->createElement('validation');
    $validation_element->appendTextNode("1");
    $response_root->appendChild($validation_element);

    my $message_element = $acknowledgment_xml->createElement('validationmessage');
    my $success_message = XML::LibXML::CDATASection->new("Success");
    $message_element->appendChild($success_message);
    $response_root->appendChild($message_element);

    $acknowledgment_xml->setDocumentElement($response_root);

    return $c->render(
        status => 200,
        text => $acknowledgment_xml->toString(),
        format => 'xml'
    );
}

1;