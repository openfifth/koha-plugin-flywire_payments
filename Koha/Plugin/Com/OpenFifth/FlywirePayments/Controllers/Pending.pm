package Koha::Plugin::Com::OpenFifth::FlywirePayments::Controllers::Pending;

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use Try::Tiny qw( catch try );

use Koha::FlywirePayments::Transactions;

sub _get_pending_accountline_ids {
    my ($borrowernumber) = @_;

    my @pending_accountline_ids;

    my $transactions = Koha::FlywirePayments::Transactions->search({
        borrowernumber => $borrowernumber,
        status         => { '-in' => ['initiated', 'processed'] }
    });

    while (my $transaction = $transactions->next) {
        if ($transaction->accountline_ids) {
            push @pending_accountline_ids, split(',', $transaction->accountline_ids);
        }
    }

    return \@pending_accountline_ids;
}

sub get_current_user {
    my $c = shift->openapi->valid_input or return;

    return try {
        my $user = $c->stash('koha.user');
        unless ($user) {
            return $c->render(
                status  => 401,
                openapi => { error => 'Not authenticated' }
            );
        }

        my $pending_ids = _get_pending_accountline_ids($user->borrowernumber);

        return $c->render(
            status  => 200,
            openapi => { pending_accountline_ids => $pending_ids }
        );

    } catch {
        warn "[FlywirePayments] Error fetching pending accountlines: $_";
        $c->unhandled_exception($_);
    };
}

1;
