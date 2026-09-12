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

// The Windows package keeps the app code obfuscated, but the exported
// AppUpdateManager name is stable and gives us a narrow, auditable patch point.
const managerPattern = /([A-Za-z_$][\w$]*)\s*\[\s*['"]AppUpdateManager['"]\s*\]\s*=\s*\{\s*['"]check['"]\s*:\s*([A-Za-z_$][\w$]*)\s*=>\s*\{/g;
const managerMatch = managerPattern.exec(source);
if (!managerMatch) {
  throw new Error('AppUpdateManager.check block was not found; upstream layout changed');
}
if (managerPattern.exec(source)) {
  throw new Error('more than one AppUpdateManager.check block was found');
}

const managerStart = managerMatch.index;
const prefix = source.slice(Math.max(0, managerStart - 5000), managerStart);
const updaterMatches = [...prefix.matchAll(/\{\s*autoUpdater\s*:\s*([A-Za-z_$][\w$]*)\s*\}/g)];
if (updaterMatches.length === 0) {
  throw new Error('autoUpdater binding was not found near AppUpdateManager');
}
const updaterVariable = updaterMatches[updaterMatches.length - 1][1];

const blockEndMarker = /\};\},0x[0-9a-f]+/;
const blockEndMatch = blockEndMarker.exec(source.slice(managerStart));
if (!blockEndMatch) {
  throw new Error('AppUpdateManager.check block terminator was not found');
}
const managerEnd = managerStart + blockEndMatch.index;
const managerBlock = source.slice(managerStart, managerEnd + 2);

const checkCall = `${updaterVariable}['checkForUpdates']()`;
const checkOffset = managerBlock.indexOf(checkCall);
if (checkOffset < 0) {
  throw new Error('AppUpdateManager.check does not call autoUpdater.checkForUpdates');
}
if (managerBlock.indexOf(checkCall, checkOffset + checkCall.length) >= 0) {
  throw new Error('multiple updater checks found in AppUpdateManager.check');
}

const feed = JSON.stringify({
  provider: 'github',
  owner,
  repo,
  releaseType: 'release',
  tagNamePrefix: 'v',
});

// Keep the existing progress/error IPC handlers, but configure the updater
// before its first check and force full AppImage downloads (no blockmap needed).
const replacement = [
  `${updaterVariable}['setFeedURL'](${feed})`,
  `${updaterVariable}['autoDownload']=!0x0`,
  `${updaterVariable}['autoInstallOnAppQuit']=!0x0`,
  `${updaterVariable}['disableDifferentialDownload']=!0x0`,
  checkCall,
].join(',');

const patchedBlock = managerBlock.slice(0, checkOffset) + replacement + managerBlock.slice(checkOffset + checkCall.length);
const patched = `${linuxCompatibilityShim}\n${source.slice(0, managerStart)}${patchedBlock}${source.slice(managerEnd + 2)}`;
fs.writeFileSync(outputPath, patched);

console.log(`configured electron-updater for github.com/${owner}/${repo}`);
