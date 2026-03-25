# Flywire Payments Plugin for Koha

Enable patrons to pay fines and charges via Flywire directly from the OPAC.

## Quick Start

### 1. Get Flywire Credentials

Contact Flywire to obtain:
- **Portal Code** (provider identifier)
- **Payment Destination** (subdomain, e.g., `kohademo`)
- **Shared Secret** (for API authentication)

### 2. Install the Plugin

**Upgrading from old plugin:** If you have the old `koha-plugin-flywire_payments` installed, you must drop the existing table before installing this version (the schema is incompatible):
```sql
DROP TABLE koha_plugin_com_openfifth_flywirepayments_flywire_transactions;
```

1. Download the latest `.kpz` file from [Releases](https://github.com/openfifth/koha-plugin-flywire_payments/releases)
2. In Koha staff interface, go to **Home > Admin > Plugins**
3. Click **Upload plugin** and select the `.kpz` file
4. Click **Install**

### 3. Restart Plack

After installation, restart Plack to load the plugin:

```bash
sudo koha-plack --restart <instance>
```

Or in KTD:
```bash
restart_all

In versions > 25.11 this will already be done on plugin upload
```

### 4. Configure the Plugin

1. Go to **Admin > Plugins > Flywire Payments > Configure**
2. Enable **OPAC Account Payments**
3. Enter your Flywire credentials:
   - Portal Code
   - Payment Destination (subdomain)
   - Shared Secret

**Using Demo Credentials:**
If testing with a demo portal, you must:
1. Enable **Debug Mode** (set to "Yes")
2. Set **Environment** to "Demo" (this option only appears when debug mode is enabled)

### 5. Test a Payment

1. **Add a charge to a patron:**
   - Staff interface > Patrons > Find patron
   - Go to **Accounting > Create manual invoice**
   - Add a charge (e.g., Lost item fee)

2. **Login as the patron in OPAC:**
   - Navigate to **Your Account > Charges**
   - Select the charge(s) to pay
   - Click **Pay**

3. **Complete payment with test card:**
   - You'll be redirected to Flywire's payment portal
   - If using a demo instance/portal - use test card details from: https://developers.flywire.com/education/Content/testing-card-payments.htm

4. **Verify in Koha:**
   - Check the patron's account in staff interface
   - Confirm payment status shows as paid
   - Transaction should appear in patron's payment history

## Troubleshooting

- **Payment option not showing in OPAC:** Ensure "Enable OPAC Account Payments" is set to Yes
- **API errors with demo credentials:** Verify Debug Mode is enabled and Environment is set to Demo
- **Callback failures:** Check that your Koha instance is accessible from the internet for Flywire callbacks

## Support

- Plugin by [OpenFifth](https://openfifth.co.uk)
- Issues: Submit via GitHub Issues
