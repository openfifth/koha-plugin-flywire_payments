# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Koha plugin that enables libraries to accept online payments from patrons using the Flywire payments platform. The plugin integrates with Koha's payment system and provides REST API endpoints for payment callbacks.

## Technology Stack

- **Language**: Perl (Modern::Perl)
- **Framework**: Koha Plugin System with Mojolicious for API routes
- **XML Processing**: XML::LibXML for Flywire payment requests/responses
- **Database**: MySQL/MariaDB (via Koha::Database)
- **Versioning**: Node.js script for version management

## Version Management

```bash
# Increment version (updates both package.json and FlywirePayments.pm)
npm run version:patch   # 0.2.3 -> 0.2.4
npm run version:minor   # 0.2.3 -> 0.3.0
npm run version:major   # 0.2.3 -> 1.0.0

# Create release (increments version, commits, tags, and pushes)
npm run release:patch
npm run release:minor
npm run release:major
```

The `increment_version.js` script automatically:
- Updates version in `package.json`
- Updates `$VERSION` in `FlywirePayments.pm`
- Updates `date_updated` in plugin metadata to today's date
- Tracks previous version in `package.json`

## Architecture

### Core Plugin Flow

1. **Payment Initiation** (`opac_online_payment_begin`):
   - Creates transaction record in plugin table
   - Builds XML payment request with patron details and accountlines
   - POSTs to Flywire payment gateway
   - Includes callback URL pointing to REST API endpoint

2. **Callback Processing** (REST API `/api/v1/contrib/flywirepayments/callback`):
   - Handled by `Controllers::Callback#process`
   - Parses incoming XML from Flywire
   - Applies payment to patron account using `Koha::Account->pay()`
   - Updates transaction table with accountline_id
   - Returns XML acknowledgment to Flywire

3. **Payment Completion** (`opac_online_payment_end`):
   - Displays payment result to patron
   - Retrieves transaction details from plugin table

### Database Schema

Plugin creates custom table `koha_plugin_com_openfifth_flywirepayments_flywire_transactions`:
- `transaction_id` (INT AUTO_INCREMENT, PRIMARY KEY)
- `accountline_id` (INT, links to Koha's accountlines table)
- `updated` (TIMESTAMP)

The transaction record is created at payment initiation with NULL `accountline_id`, then updated via callback when payment is processed.

### REST API Integration

The plugin extends Koha's REST API by implementing:
- `api_namespace()`: Returns 'flywirepayments'
- `api_routes()`: Returns OpenAPI spec from `api/openapi.json`
- Route: POST `/api/v1/contrib/flywirepayments/callback`

### Object Model

- `Koha::FlywirePayments::Transaction`: Single transaction object
- `Koha::FlywirePayments::Transactions`: Collection of transactions
- Uses Koha's DBIx::Class-based schema registration
- Schema result class: `Koha::Schema::Result::KohaPluginComOpenfifthFlywirepaymentsFlywireTransaction`

### Key Components

**FlywirePayments.pm** (main plugin file):
- Implements Koha::Plugins::Base hooks
- XML construction for Flywire payment requests
- Configuration management (credentials, VAT settings, custom fields)
- Payment initialization and completion handlers
- Schema registration in BEGIN block (critical for plugin lib loading)

**Controllers/Callback.pm** (REST API controller):
- Mojolicious controller for payment callbacks
- XML parsing and validation
- Payment application via Koha::Account
- User environment setup for payment processing
- Legacy support for item renewal (pre-20.05 Koha versions)

### Koha Version Compatibility

Plugin checks Koha version using `_version_check()` for compatibility:
- **Pre-19.11**: Uses `accounttype` field
- **19.11+**: Uses `debit_type_code` relationship
- **Pre-20.05**: Handles old payment return format (scalar vs hashref)
- **20.05+**: Uses `payment_id` from payment result hashref

System type mapping for legacy Flywire compatibility:
```perl
'OVERDUE' => 'F'  # Fine
'LOST'    => 'L'  # Lost item
```

## Configuration

Plugin stores configuration via `store_data()`:
- Flywire credentials (ClientID, Secret, PathwayID, DepartmentID)
- VAT settings (Description, Code, Rate)
- Custom fields 1-10 (support template variables like `[% borrower.cardnumber %]`)
- Payment custom field 1

Configuration UI uses Template Toolkit template `configure.tt`.

## Important Implementation Details

### MD5 Signature Generation
Payment requests include MD5 signature for security:
```perl
md5_hex($ClientID . $transaction_id . $total_amount . $Secret)
```

### User Environment Handling
Callback controller sets C4::Context userenv if not present, required for Koha::Account operations.

### OPAC Template Files
- `opac_online_payment_begin.tt`: Payment initiation form (auto-POSTs XML to Flywire)
- `opac_online_payment_end.tt`: Payment confirmation page
- `opac_online_payment_error.tt`: Error page

### Library Loading
Plugin uses `BEGIN` block to:
1. Find plugin path via `Module::Metadata`
2. Add `lib/` subdirectory to `@INC`
3. Load custom classes (Transaction, Transactions, Schema)
4. Register schema with Koha's DBIx::Class

## Plugin Migration (Rebranding)

### Background
In commit `2237e727`, the plugin was rebranded from PTFSEurope/WPMPayments to OpenFifth/FlywirePayments to reflect:
- Company name change: PTFS Europe → OpenFifth
- Payment platform rebrand: WPM → Flywire

This changed the plugin class name, making Koha treat it as a new plugin.

### Automatic Migration (upgrade method)
The `upgrade()` method automatically migrates from the old plugin when detected:

**Configuration Migration:**
- Old keys → New keys:
  - `WPMClientID` → `FlywireClientID`
  - `WPMSecret` → `FlywireSecret`
  - `WPMPathway` → `FlywirePathway`
  - `WPMPathwayID` → `FlywirePathwayID`
  - `WPMDepartmentID` → `FlywireDepartmentID`
- Other keys (VAT settings, customfields) are copied as-is

**Transaction Data Migration:**
- Copies all records from `koha_plugin_com_ptfseurope_wpmpayments_wpm_transactions` to new table
- Drops old transaction table after migration
- Avoids duplicates using transaction_id checks

**Cleanup:**
- Removes old plugin from `plugin_methods` table
- Removes old plugin from `plugin_data` table

The migration runs automatically on plugin upgrade and logs progress via `warn()` statements.

## Development Notes

- Plugin file must maintain version in both `our $VERSION` and `$metadata->{version}`
- Minimum Koha version: 23.11.00.000
- No KPZ build script provided; plugin is distributed as .kpz (zip) file
- Debug mode available via `$debug` variable (warns to logs)
