# Introduction

This Koha plugin enables a library to accept online payments from patrons using the Flywire payments platform.

Plugins are installed by uploading KPZ ( Koha Plugin Zip ) packages. A KPZ file is just a zip file containing the perl files, template files, and any other files necessary to make the plugin work. Learn more about the Koha Plugin System in the [Koha 3.22 Manual](http://manual.koha-community.org/3.22/en/pluginsystem.html).

# Downloading

From the [release page](https://github.com/openfifth/koha-plugin-flywirepayments/releases) you can download the relevant *.kpz file

# Installing

To set up the Koha plugin system you must first make some changes to your install.

* Change `<enable_plugins>0<enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your koha-conf.xml file
* Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server
* Add the pluginsdir to your apache PERL5LIB paths and koha-plack startup scripts PERL5LIB
* Restart your webserver

Once set up is complete you will need to alter your UseKohaPlugins system preference. On the Tools page you will see the Tools Plugins and on the Reports page you will see the Reports Plugins.

# Setup

The plugin now uses Koha's REST API for payment callbacks, eliminating the need for Apache configuration directives.

## API Endpoint

The Flywire callback endpoint is now available at:
```
/api/v1/contrib/flywirepayments/callback
```

This endpoint accepts POST requests with XML payloads from the Flywire payment system.

## Legacy Setup (Deprecated)

Previous versions required Apache configuration for CGI script access. This is no longer needed with the API-based approach
