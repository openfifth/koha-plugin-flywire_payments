#!/usr/bin/perl

use Modern::Perl;
use lib '/kohadevbox/koha';
use lib '.';

use Koha::Plugin::Com::OpenFifth::FlywirePayments;

my $plugin = Koha::Plugin::Com::OpenFifth::FlywirePayments->new;

print "=== Flywire Plugin Configuration Debug ===\n\n";

my @config_keys = qw(
    enable_opac_payments
    FlywireClientID
    FlywireSecret
    FlywirePathway
    FlywirePathwayID
    FlywireDepartmentID
);

foreach my $key (@config_keys) {
    my $value = $plugin->retrieve_data($key) || '[NOT SET]';
    $value = '[HIDDEN]' if $key =~ /secret/i && $value ne '[NOT SET]';
    print sprintf("%-20s: %s\n", $key, $value);
}

print "\n=== XML Generation Test ===\n";
print "API Namespace: " . $plugin->api_namespace . "\n";
print "Version: " . $plugin->{metadata}->{version} . "\n";

# Check if essential configs are set
my $client_id = $plugin->retrieve_data('FlywireClientID');
my $pathway = $plugin->retrieve_data('FlywirePathway');
my $pathway_id = $plugin->retrieve_data('FlywirePathwayID');

print "\n=== Status ===\n";
if (!$client_id || !$pathway || !$pathway_id) {
    print "❌ MISSING CONFIGURATION!\n";
    print "Required fields: FlywireClientID, FlywirePathway, FlywirePathwayID\n";
} else {
    print "✅ Essential configuration present\n";
}