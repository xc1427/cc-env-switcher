const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..');
const pkgDir = path.join(root, 'publish');
const pkg = require(path.join(pkgDir, 'package.json'));
const launcher = path.join(pkgDir, 'bin/cc-env-switcher.js');
const app = path.join(pkgDir, 'cc-env-switcher.app');
test('packaged launcher reports version and validates arguments without launching', () => {
  assert.equal(execFileSync(process.execPath, [launcher, '--version'], {encoding:'utf8'}).trim(), pkg.version);
  assert.match(execFileSync(process.execPath, [launcher, '--help'], {encoding:'utf8'}), /Usage:/);
  assert.equal(spawnSync(process.execPath, [launcher, '--unknown']).status, 1);
});
test('native app has a valid signature, both architectures, and matching bundle version', () => {
  execFileSync('codesign', ['--verify', '--deep', '--strict', app]);
  execFileSync('lipo', [path.join(app, 'Contents/MacOS/cc-env-switcher'), '-verify_arch', 'arm64', 'x86_64']);
  assert.equal(execFileSync('/usr/libexec/PlistBuddy', ['-c','Print :CFBundleShortVersionString',path.join(app,'Contents/Info.plist')],{encoding:'utf8'}).trim(),pkg.version);
  assert.deepEqual(pkg.os,['darwin']);
  assert.deepEqual(pkg.cpu,['arm64','x64']);
});
test('npm package contains only distribution files and has no install scripts', () => {
  const [pack] = JSON.parse(execFileSync('npm',['pack','--dry-run','--json','--ignore-scripts'],{cwd:pkgDir,encoding:'utf8'}));
  assert.equal(pkg.scripts,undefined);
  assert.equal(pkg.license,'MIT');
  for (const {path:p} of pack.files) assert.match(p,/^(package\.json|README\.md|LICENSE|CHANGELOG\.md|bin\/cc-env-switcher\.js|cc-env-switcher\.app\/)/);
  assert.ok(fs.statSync(path.join(app,'Contents/MacOS/cc-env-switcher')).mode & 0o111);
});
