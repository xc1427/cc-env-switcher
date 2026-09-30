#!/usr/bin/env node
'use strict';
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const pkg = require('../package.json');
const args = process.argv.slice(2);
if (args.length === 1 && ['--version', '-v'].includes(args[0])) {
  console.log(pkg.version);
} else if (args.length === 1 && ['--help', '-h'].includes(args[0])) {
  console.log('Usage: cc-env-switcher [--version | --help]\nOpens the native macOS environment profile switcher.');
} else if (args.length) {
  console.error('Unknown argument. Run cc-env-switcher --help.');
  process.exitCode = 1;
} else if (process.platform !== 'darwin') {
  console.error('cc-env-switcher requires macOS 13 or later.');
  process.exitCode = 1;
} else {
  const result = spawnSync('/usr/bin/open', [path.join(__dirname, '..', 'cc-env-switcher.app')], { stdio: 'inherit' });
  if (result.error) console.error(result.error.message);
  process.exitCode = result.status ?? 1;
}
