#!/usr/bin/env node

/**
 * Usage:
 *   node increment_version.js patch   # 1.0.0 -> 1.0.1
 *   node increment_version.js minor   # 1.0.0 -> 1.1.0
 *   node increment_version.js major   # 1.0.0 -> 2.0.0
 */

const fs = require('fs');
const path = require('path');

const PACKAGE_JSON_PATH = path.join(__dirname, 'package.json');
const PLUGIN_PM_PATH = path.join(__dirname, 'Koha', 'Plugin', 'Com', 'OpenFifth', 'FlywirePayments.pm');

function incrementVersion(version, type) {
    const parts = version.split('.').map(Number);
    
    switch (type) {
        case 'major':
            parts[0]++;
            parts[1] = 0;
            parts[2] = 0;
            break;
        case 'minor':
            parts[1]++;
            parts[2] = 0;
            break;
        case 'patch':
        default:
            parts[2]++;
            break;
    }
    
    return parts.join('.');
}

function getTodayDate() {
    const today = new Date();
    const year = today.getFullYear();
    const month = String(today.getMonth() + 1).padStart(2, '0');
    const day = String(today.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

function main() {
    const type = process.argv[2] || 'patch';
    
    if (!['major', 'minor', 'patch'].includes(type)) {
        console.error('Usage: node increment_version.js [major|minor|patch]');
        process.exit(1);
    }
    
    const packageJson = JSON.parse(fs.readFileSync(PACKAGE_JSON_PATH, 'utf8'));
    const oldVersion = packageJson.version;
    const newVersion = incrementVersion(oldVersion, type);
    
    packageJson.previousVersion = oldVersion;
    packageJson.version = newVersion;
    
    fs.writeFileSync(PACKAGE_JSON_PATH, JSON.stringify(packageJson, null, 2) + '\n');
    console.log(`Updated package.json: ${oldVersion} -> ${newVersion}`);
    
    let pluginContent = fs.readFileSync(PLUGIN_PM_PATH, 'utf8');
    
    pluginContent = pluginContent.replace(
        /our \$VERSION = '[^']+';/,
        `our $VERSION = '${newVersion}';`
    );
    
    const todayDate = getTodayDate();
    pluginContent = pluginContent.replace(
        /date_updated\s+=>\s+'[^']+'/,
        `date_updated    => '${todayDate}'`
    );
    
    fs.writeFileSync(PLUGIN_PM_PATH, pluginContent);
    console.log(`Updated FlywirePayments.pm: $VERSION = '${newVersion}', date_updated = '${todayDate}'`);
    
    console.log(`\nVersion bumped from ${oldVersion} to ${newVersion}`);
}

main();
