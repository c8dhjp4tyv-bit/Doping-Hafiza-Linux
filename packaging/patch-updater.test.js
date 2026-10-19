'use strict';

const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function patch(t, source) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'doping-updater-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const input = path.join(directory, 'main.js');
  const output = path.join(directory, 'patched.js');
  fs.writeFileSync(input, source);
  const result = spawnSync(process.execPath, [path.join(__dirname, 'patch-updater.js'), input, output], {
    encoding: 'utf8',
    env: { ...process.env, DOPING_UPDATE_OWNER: 'test-owner', DOPING_UPDATE_REPO: 'test-repo' },
  });
  return { ...result, patched: fs.existsSync(output) ? fs.readFileSync(output, 'utf8') : null };
}

for (const call of ["updater['checkForUpdates']()", 'updater[decode(0x14ad)]()']) {
  test(`configures before ${call} and preserves upstream callbacks`, async (t) => {
    const body = `const decode = key => key === 0x14ad ? 'checkForUpdates' : 'catch';
      updater['on']('download-progress', progress => callback(progress.percent));
      updater['on']('error', () => callback(null));
      ${call}[decode(0x43d3)](() => callback(null));`;
    const source = `const {autoUpdater: updater} = require('electron-updater');
      updater.autoDownload = false;
      exports['AppUpdateManager'] = {'check': callback => {${body}}};`;
    const result = patch(t, source);
    assert.equal(result.status, 0, result.stderr);
    assert.ok(result.patched.includes(body), 'upstream body must remain byte-for-byte intact');
    const handlers = {};
    const events = [];
    const callbacks = [];
    const updater = {
      setFeedURL(feed) { events.push('feed'); this.feed = feed; },
      on(name, callback) { events.push(name); handlers[name] = callback; },
      checkForUpdates() {
        events.push('check');
        assert.equal(this.feed.owner, 'test-owner');
        assert.equal(this.feed.repo, 'test-repo');
        assert.equal(this.feed.provider, 'github');
        assert.equal(this.autoDownload, true);
        assert.equal(this.autoInstallOnAppQuit, true);
        assert.equal(this.disableDifferentialDownload, true);
        return Promise.reject(new Error('upstream failure'));
      },
    };
    const exports = {};
    vm.runInNewContext(result.patched, {
      exports,
      process: { platform: 'linux' },
      require(name) {
        if (name === 'electron-updater') return { autoUpdater: updater };
        if (name === 'electron') return { app: {}, systemPreferences: {} };
        throw new Error(`unexpected module: ${name}`);
      },
    });
    assert.deepEqual(events, []);
    exports.AppUpdateManager.check(value => callbacks.push(value));
    handlers['download-progress']({ percent: 42 });
    handlers.error();
    await Promise.resolve();
    assert.deepEqual(events, ['download-progress', 'error', 'feed', 'check']);
    assert.deepEqual(callbacks, [42, null, null]);
  });
}

test('supports a renamed manager with an obfuscated updater reference', (t) => {
  const source = `const {autoUpdater:_0xa} = require('electron-updater');
    exports.run = () => _0xa[decode(0x2)]();
    function decode() { return 'checkForUpdates'; }`;
  const result = patch(t, source);
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.patched.includes(source), 'upstream source must remain unchanged');
  const events = [];
  const updater = {
    setFeedURL(feed) { events.push('feed'); this.feed = feed; },
    checkForUpdates() {
      events.push('check');
      assert.equal(this.feed.owner, 'test-owner');
      assert.equal(this.autoDownload, true);
    },
  };
  const exports = {};
  vm.runInNewContext(result.patched, {
    exports,
    process: { platform: 'linux' },
    require(name) {
      if (name === 'electron') return { app: {}, systemPreferences: {} };
      if (name === 'electron-updater') return { autoUpdater: updater };
      throw new Error(`unexpected module: ${name}`);
    },
  });
  assert.deepEqual(events, []);
  exports.run();
  assert.deepEqual(events, ['feed', 'check']);
});

test('wraps checkForUpdatesAndNotify without changing its return value', (t) => {
  const source = `const {autoUpdater: u} = require('electron-updater');
    exports.poll = () => u.checkForUpdatesAndNotify('arg');`;
  const result = patch(t, source);
  assert.equal(result.status, 0, result.stderr);
  const events = [];
  const updater = {
    setFeedURL(feed) { events.push('feed'); this.feed = feed; },
    checkForUpdatesAndNotify(value) {
      events.push('notify');
      assert.equal(value, 'arg');
      assert.equal(this.feed.repo, 'test-repo');
      assert.equal(this.disableDifferentialDownload, true);
      return 123;
    },
  };
  const exports = {};
  vm.runInNewContext(result.patched, {
    exports, process: { platform: 'linux' },
    require(name) {
      if (name === 'electron') return { app: {}, systemPreferences: {} };
      if (name === 'electron-updater') return { autoUpdater: updater };
      throw new Error(`unexpected module: ${name}`);
    },
  });
  assert.equal(exports.poll(), 123);
  assert.deepEqual(events, ['feed', 'notify']);
});

test('rejects a source with no electron-updater integration', (t) => {
  const result = patch(t, 'const unrelated = {};');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /integration was not found/);
  assert.equal(result.patched, null);
});
