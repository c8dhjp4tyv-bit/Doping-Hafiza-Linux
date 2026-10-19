#!/usr/bin/env node
'use strict';

const fs = require('fs');

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  console.error('usage: patch-updater.js INPUT_MAIN_JS OUTPUT_MAIN_JS');
  process.exit(2);
}

const owner = process.env.DOPING_UPDATE_OWNER || 'c8dhjp4tyv-bit';
const repo = process.env.DOPING_UPDATE_REPO || 'Doping-Hafiza-Linux';
const source = fs.readFileSync(inputPath, 'utf8');

// The upstream renderer asks the main process to check microphone/camera
// permissions before opening the coaching appointment flow. Electron exposes
// systemPreferences.getMediaAccessStatus/askForMediaAccess on macOS only, so
// the unmodified bundle rejects that IPC call on Linux with a TypeError. The
// upstream app also starts a second Electron runtime with --helper; command
// line switches passed to AppRun are not inherited by that child. Install the
// Linux compatibility workarounds in every main process so media IPC remains
// callable and the helper cannot re-enable the problematic NVIDIA/Wayland GPU
// path.
const linuxCompatibilityShim = [
  ';(() => {',
  "  if (process.platform !== 'linux') return;",
  '  try {',
  "    const { app, systemPreferences } = require('electron');",
  "    if (app && typeof app.disableHardwareAcceleration === 'function') app.disableHardwareAcceleration();",
  "    if (app && app.commandLine && typeof app.commandLine.appendSwitch === 'function') {",
  "      app.commandLine.appendSwitch('disable-gpu');",
  "      app.commandLine.appendSwitch('disable-gpu-compositing');",
  "      app.commandLine.appendSwitch('use-gl', 'disabled');",
  '    }',
  '    const installFallback = (name, fallback) => {',
  '      if (typeof systemPreferences[name] === \'function\') return;',
  '      try {',
  '        Object.defineProperty(systemPreferences, name, {',
  '          configurable: true,',
  '          enumerable: true,',
  '          writable: true,',
  '          value: fallback,',
  '        });',
  '      } catch {',
  '        try { systemPreferences[name] = fallback; } catch {}',
  '      }',
  '    };',
  "    installFallback('getMediaAccessStatus', () => 'granted');",
  "    installFallback('askForMediaAccess', async () => true);",
  '  } catch (error) {',
  "    console.warn('[doping-hafiza] Linux graphics/media compatibility setup failed', error);",
  '  }',
  '})();',
].join('\n');

// Upstream obfuscation can rename AppUpdateManager and change the shape of
// its check callback. The electron-updater singleton and its public methods
// are the stable integration point: configure immediately before a check,
// even when upstream calls the method via a computed property name.
// Fail closed when the upstream bundle no longer references electron-updater.
if (!/\b(?:autoUpdater|electron-updater)\b/.test(source)) {
  throw new Error('electron-updater integration was not found; upstream layout changed');
}

const feed = {
  provider: 'github',
  owner,
  repo,
  releaseType: 'release',
  tagNamePrefix: 'v',
};

const updaterRuntimeShim = [
  ";(() => {",
  "  if (process.platform !== 'linux') return;",
  "  const { autoUpdater } = require('electron-updater');",
  "  if (!autoUpdater || typeof autoUpdater.setFeedURL !== 'function') {",
  "    throw new Error('electron-updater does not expose a configurable autoUpdater');",
  "  }",
  "  const feed = " + JSON.stringify(feed) + ";",
  "  const configure = () => {",
  "    autoUpdater.setFeedURL(feed);",
  "    autoUpdater.autoDownload = true;",
  "    autoUpdater.autoInstallOnAppQuit = true;",
  "    autoUpdater.disableDifferentialDownload = true;",
  "  };",
  "  let patchedChecks = 0;",
  "  for (const methodName of ['checkForUpdates', 'checkForUpdatesAndNotify']) {",
  "    const original = autoUpdater[methodName];",
  "    if (typeof original !== 'function') continue;",
  "    autoUpdater[methodName] = function (...args) {",
  "      configure();",
  "      return Reflect.apply(original, this, args);",
  "    };",
  "    patchedChecks += 1;",
  "  }",
  "  if (patchedChecks === 0) {",
  "    throw new Error('electron-updater has no supported update-check method');",
  "  }",
  "})();",
].join('\n');

// Keep the upstream main bundle byte-for-byte intact; prepend small shims.
const patched = `${linuxCompatibilityShim}\n${updaterRuntimeShim}\n${source}`;
fs.writeFileSync(outputPath, patched);

console.log(`configured electron-updater for github.com/${owner}/${repo}`);
