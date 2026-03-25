use utf8;

package Koha::Plugin::Com::OpenFifth::FlywirePayments;

use Modern::Perl;

use base qw(Koha::Plugins::Base);
use version 0.77;

use C4::Context;
use C4::Auth qw( get_template_and_user );
use Koha::Account;
use Koha::Account::Lines;
use Koha::Patrons;
use Koha::Database;

BEGIN {
    my $path = Module::Metadata->find_module_by_name(__PACKAGE__);
    $path =~ s{[.]pm$}{/lib}xms;
    unshift @INC, $path;

    require Koha::FlywirePayments::Transactions;
    require Koha::Schema::Result::KohaPluginComOpenfifthFlywirepaymentsFlywireTransaction;
    Koha::Schema->register_class(
        KohaPluginComOpenfifthFlywirepaymentsFlywireTransaction => 'Koha::Schema::Result::KohaPluginComOpenfifthFlywirepaymentsFlywireTransaction'
    );

    Koha::Database->schema({ new => 1 });
}

use Digest::SHA qw(hmac_sha256);
use MIME::Base64 qw(encode_base64);
use JSON qw(encode_json decode_json);
use LWP::UserAgent;
use HTTP::Request;
use URI;
use DateTime;
use Module::Metadata;
use Try::Tiny qw(try catch);

## Here we set our plugin version
our $VERSION = '1.0.0';

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'Flywire Payments Plugin',
    author          => 'OpenFifth',
    date_authored   => '2025-01-06',
    date_updated    => '2026-03-25',
    minimum_version => '23.11.00.000',
    maximum_version => '',
    version         => $VERSION,
    description     => 'This plugin implements online payments using '
      . 'the Flywire API.',
};

## Flywire API endpoints
our %API_ENDPOINTS = (
    demo       => 'https://gateway.demo.flywire.com/v1/transfers.json',
    production => 'https://gateway.flywire.com/v1/transfers.json',
);

sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

sub _version_check {
    my ( $self, $minversion ) = @_;

    my $kohaversion = Koha::version();
    return ( version->parse($kohaversion) > version->parse($minversion) );
}

=head2 _is_debug_mode

Check if debug mode is enabled in plugin configuration

=cut

sub _is_debug_mode {
    my ($self) = @_;

    return $self->retrieve_data('FlywireDebugMode') eq 'Yes';
}

sub opac_online_payment {
    my ( $self, $args ) = @_;

    return $self->retrieve_data('enable_opac_payments') eq 'Yes';
}

=head2 _generate_flywire_digest

Generate HMAC-SHA256 digest for Flywire API authentication

=cut

sub _generate_flywire_digest {
    my ( $self, $json_body ) = @_;

    my $shared_secret = $self->retrieve_data('FlywireSharedSecret');
    my $hmac = hmac_sha256($json_body, $shared_secret);
    my $digest = encode_base64($hmac, '');  # '' prevents newlines

    return $digest;
}

=head2 _get_api_endpoint

Get the appropriate Flywire API endpoint based on environment setting

=cut

sub _get_api_endpoint {
    my ($self) = @_;

    my $environment = $self->retrieve_data('FlywireEnvironment') || 'production';
    return $API_ENDPOINTS{$environment};
}

=head2 _create_payment_link

Create a payment link via Flywire Pay-by-Link API

=cut

sub _create_payment_link {
    my ( $self, $payload ) = @_;

    my $json_body = encode_json($payload);
    my $digest = $self->_generate_flywire_digest($json_body);
    my $endpoint = $self->_get_api_endpoint();

$self->_is_debug_mode and warn "[FlywirePayments] Creating payment link at: $endpoint";
        $self->_is_debug_mode and warn "[FlywirePayments] Payload: $json_body";

    my $ua = LWP::UserAgent->new(
        timeout => 30,
        ssl_opts => { verify_hostname => 1 }
    );

    my $request = HTTP::Request->new('POST', $endpoint);
    $request->header('Content-Type' => 'application/json');
    $request->header('X-Flywire-Digest' => $digest);
    $request->content($json_body);

    my $response = $ua->request($request);

    if ($response->is_success) {
        my $result = decode_json($response->decoded_content);
        $self->_is_debug_mode and warn "[FlywirePayments] API Response: " . $response->decoded_content;
        return { success => 1, data => $result };
    } else {
        warn "[FlywirePayments] API Error: " . $response->status_line;
        warn "[FlywirePayments] Response: " . $response->decoded_content;
        return { success => 0, error => $response->status_line, details => $response->decoded_content };
    }
}

=head2 opac_online_payment_begin

Initiate online payment process via Flywire Pay-by-Link

=cut

sub opac_online_payment_begin {
    my ( $self, $args ) = @_;
    $self->_is_debug_mode and warn "Inside opac_online_payment_begin for: " . caller . "\n";

    my $cgi    = $self->{'cgi'};
    my $schema = Koha::Database->new()->schema();

    my ( $template, $borrowernumber ) = get_template_and_user(
        {
            template_name   => $self->mbf_path('opac_online_payment_begin.tt'),
            query           => $cgi,
            type            => 'opac',
            authnotrequired => 0,
            is_plugin       => 1,
        }
    );

    # Get the borrower
    my $borrower = Koha::Patrons->find($borrowernumber);

    # Get the accountlines to pay
    my @accountline_ids = $cgi->multi_param('accountline');
    my $accountlines = $schema->resultset('Accountline')
        ->search( { accountlines_id => \@accountline_ids } );

    # Calculate total amount in pence (subunits)
    my $total_amount_decimal = 0;
    my @line_descriptions;
    for my $accountline ( $accountlines->all ) {
        my $amount = sprintf "%.2f", $accountline->amountoutstanding;
        $total_amount_decimal += $amount;
        push @line_descriptions, $accountline->description || 'Library charge';
    }
    # Convert to pence (multiply by 100)
    my $total_amount_pence = int($total_amount_decimal * 100);

    # Create a transaction record
    my $transaction = Koha::FlywirePayments::Transaction->new({
        borrowernumber          => $borrowernumber,
        amount                  => $total_amount_pence,
        charge_accountline_ids  => join(',', @accountline_ids),
        status                  => 'pending',
    })->store();
    my $transaction_id = $transaction->transaction_id;

    # Construct callback URI
    my $callback_url = URI->new(
        C4::Context->preference('OPACBaseURL')
        . "/api/v1/contrib/" . $self->api_namespace . "/callback"
    );

    # Construct return URL (redirect after payment)
    my $return_url = URI->new(
        C4::Context->preference('OPACBaseURL')
        . "/cgi-bin/koha/opac-account-pay-return.pl"
    );
    $return_url->query_form({
        payment_method => scalar $cgi->param('payment_method'),
        transaction_id => $transaction_id
    });

    # Build the Pay-by-Link payload
    my $payload = {
        provider            => $self->retrieve_data('FlywireProvider'),
        payment_destination => $self->retrieve_data('FlywirePaymentDestination'),
        amount              => $total_amount_pence,
        max_amount          => $total_amount_pence,
        country             => $borrower->country || 'GB',

        # Payer information
        sender_email        => $borrower->email,
        sender_first_name   => $borrower->firstname,
        sender_last_name    => $borrower->surname,
        sender_address1     => $borrower->address,
        sender_city         => $borrower->city,
        sender_zip          => $borrower->zipcode,

        # Dynamic fields (required by Flywire for this portal)
        dynamic_fields => {
            student_first_name => $borrower->firstname,
            student_last_name  => $borrower->surname,
            student_id         => $borrower->cardnumber,
            student_email      => $borrower->email,
        },

        # Callback settings
        callback_url     => $callback_url->as_string,
        callback_id      => $transaction_id,  # Our reference for matching callbacks
        callback_version => '2',

        # Return URL
        return_cta      => $return_url->as_string,
        return_cta_name => 'Return to Library',

        # Link expiration (days)
        days_to_expire => 7,
    };

    # Add state if available
    if ($borrower->state) {
        $payload->{sender_state} = $borrower->state;
    }

    # Call Flywire API to create payment link
    my $result = $self->_create_payment_link($payload);

    if ($result->{success}) {
        # Extract the payment URL from response
        my $payment_url = $result->{data}->{url};
        my $flywire_reference = $result->{data}->{id} || $result->{data}->{payment_id};

        # Update transaction with Flywire reference
        $transaction->flywire_reference($flywire_reference);
        $transaction->store();

        $template->param(
            payment_url => $payment_url,
            borrower    => $borrower,
            amount      => sprintf("%.2f", $total_amount_decimal),
        );
    } else {
        # Handle error
        $template->param(
            error         => 1,
            error_message => $result->{error},
            error_details => $result->{details},
            borrower      => $borrower,
        );
    }

    print $cgi->header();
    print $template->output();
}

=head2 opac_online_payment_end

Complete online payment process

=cut

sub opac_online_payment_end {
    my ( $self, $args ) = @_;

    $self->_is_debug_mode and warn "Inside opac_online_payment_end for: " . caller . "\n";
    my $cgi = $self->{'cgi'};

    my ( $template, $borrowernumber ) = get_template_and_user(
        {
            template_name   => $self->mbf_path('opac_online_payment_end.tt'),
            query           => $cgi,
            type            => 'opac',
            authnotrequired => 0,
            is_plugin       => 1,
        }
    );

    my $transaction_id = $cgi->param('transaction_id');

    # Check payment status
    my $transaction = Koha::FlywirePayments::Transactions->find($transaction_id);

    if ($transaction) {
        my $status = $transaction->status;

        if ($status eq 'guaranteed' || $status eq 'delivered') {
            # Payment was successful
            my $amount_pence = $transaction->amount;
            my $amount_decimal = sprintf("%.2f", $amount_pence / 100);

            $template->param(
                borrower      => scalar Koha::Patrons->find($borrowernumber),
                message       => 'valid_payment',
                message_value => $amount_decimal,
                status        => $status,
            );
        } elsif ($status eq 'pending' || $status eq 'initiated' || $status eq 'processed') {
            # Payment is still processing
            $template->param(
                borrower => scalar Koha::Patrons->find($borrowernumber),
                message  => 'payment_pending',
                status   => $status,
            );
        } else {
            # Payment failed or was cancelled
            $template->param(
                borrower => scalar Koha::Patrons->find($borrowernumber),
                message  => 'payment_failed',
                status   => $status,
            );
        }
    } else {
        $template->param(
            borrower => scalar Koha::Patrons->find($borrowernumber),
            message  => 'no_transaction'
        );
    }

    print $cgi->header();
    print $template->output();
}

sub opac_js {
    my ($self) = @_;

    return <<'END_JS';
        <script>
        $(document).ready(function() {
            if (!window.location.pathname.match(/opac-account(-pay)?\.pl/)) {
                return;
            }

            var pendingIds = [];

            function markPendingPayments() {
                if (pendingIds.length === 0) {
                    return;
                }

                pendingIds.forEach(function(accountlineId) {
                    var $checkbox = $('#checkbox-pay-' + accountlineId);
                    if ($checkbox.length && !$checkbox.data('flywire-marked')) {
                        $checkbox.prop('disabled', true);
                        $checkbox.prop('checked', false);
                        $checkbox.data('flywire-marked', true);
                        
                        var $row = $checkbox.closest('tr');
                        $row.addClass('flywire-payment-pending');
                        $row.css('opacity', '0.6');
                        
                        var $descCell = $row.find('td').eq(4);
                        if ($descCell.length && $descCell.find('.flywire-pending-badge').length === 0) {
                            $descCell.append(' <span class="flywire-pending-badge badge" style="background-color: #f0ad4e; color: white; padding: 2px 6px; border-radius: 3px; font-size: 0.85em; margin-left: 5px;">Payment in progress</span>');
                        }
                    }
                });
            }

            $.ajax({
                url: '/api/v1/contrib/flywirepayments/pending',
                method: 'GET',
                dataType: 'json',
                success: function(response) {
                    pendingIds = response.pending_accountline_ids || [];
                    markPendingPayments();
                    
                    if (typeof $.fn.DataTable !== 'undefined') {
                        $('#finestable').on('draw.dt', function() {
                            markPendingPayments();
                        });
                    }
                },
                error: function(xhr, status, error) {
                    console.log('FlywirePayments: Could not fetch pending payments', error);
                }
            });
        });
        </script>
END_JS
}

## Configuration page
sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            enable_opac_payments      => $self->retrieve_data('enable_opac_payments'),
            FlywireProvider           => $self->retrieve_data('FlywireProvider'),
            FlywirePaymentDestination => $self->retrieve_data('FlywirePaymentDestination'),
            FlywireSharedSecret       => $self->retrieve_data('FlywireSharedSecret'),
            FlywireEnvironment        => $self->retrieve_data('FlywireEnvironment'),
            FlywireDebugMode          => $self->retrieve_data('FlywireDebugMode'),
        );

        print $cgi->header();
        print $template->output();
    }
    else {
        $self->store_data(
            {
                enable_opac_payments      => scalar $cgi->param('enable_opac_payments'),
                FlywireProvider           => scalar $cgi->param('FlywireProvider'),
                FlywirePaymentDestination => scalar $cgi->param('FlywirePaymentDestination'),
                FlywireSharedSecret       => scalar $cgi->param('FlywireSharedSecret'),
                FlywireEnvironment        => scalar $cgi->param('FlywireEnvironment'),
                FlywireDebugMode          => scalar $cgi->param('FlywireDebugMode'),
                last_configured_by        => C4::Context->userenv->{'number'},
            }
        );
        $self->go_home();
    }
}

## Install method - creates database tables
sub install() {
    my ( $self, $args ) = @_;

    my $table = $self->get_qualified_table_name('flywire_transactions');

    return C4::Context->dbh->do( "
        CREATE TABLE IF NOT EXISTS $table (
            `transaction_id` INT( 11 ) NOT NULL AUTO_INCREMENT,
            `borrowernumber` INT( 11 ),
            `payment_accountline_id` INT( 11 ),
            `charge_accountline_ids` TEXT,
            `amount` INT( 11 ),
            `flywire_reference` VARCHAR( 255 ),
            `status` VARCHAR( 50 ) DEFAULT 'pending',
            `updated` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            `created` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`transaction_id`),
            INDEX (`borrowernumber`),
            INDEX (`flywire_reference`),
            INDEX (`status`)
        ) ENGINE = INNODB;
    " );
}

## Upgrade method
sub upgrade {
    my ( $self, $args ) = @_;

    my $dbh = C4::Context->dbh;
    my $dt = DateTime->now;

    $self->store_data(
        { last_upgraded => $dt->ymd('-') . ' ' . $dt->hms(':') }
    );

    return 1;
}

=head3 api_namespace

Define the namespace for the plugin's API routes

=cut

sub api_namespace {
    my ($self) = @_;

    return 'flywirepayments';
}

=head3 api_routes

Define the API routes provided by this plugin

=cut

sub api_routes {
    my ($self) = @_;

    my $spec_str = $self->mbf_read('api/openapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

=head3 validate_callback_signature

Validate the HMAC signature of incoming callbacks

=cut

sub validate_callback_signature {
    my ( $self, $body, $received_digest ) = @_;

    my $expected_digest = $self->_generate_flywire_digest($body);

    return $received_digest eq $expected_digest;
}

1;
