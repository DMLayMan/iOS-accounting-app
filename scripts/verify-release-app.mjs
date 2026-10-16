// Read-only resource/configuration gate. Signature, provisioning and live services are separate.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const app = process.argv[2];
if (!app || !app.endsWith('.app') || process.argv.length !== 3) {
  console.error('Usage: node scripts/verify-release-app.mjs PATH/TO/Yuji.app');
  process.exit(2);
}
const readPlist = file => JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', file], { encoding: 'utf8' }));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const info = readPlist(path.join(app, 'Info.plist'));
const binaryPath = path.join(app, info.CFBundleExecutable);
const binary = fs.readFileSync(binaryPath);
const symbols = execFileSync('nm', [binaryPath], { encoding: 'utf8', maxBuffer: 20_000_000 });
const privacy = readPlist(path.join(app, 'PrivacyInfo.xcprivacy'));
const markers = ['YUJI_STRESS_SESSION', 'YUJI_UI_TEST_SESSION', 'YUJI_TEST_CLOUD_MODE',
  'YUJI_TEST_SUPPORT_MODE', 'YUJI_LIVE_FIXTURE_CLEANUP'];
const checks = {
  bundle: info.CFBundleIdentifier === 'com.dmlayman.yuji',
  displayName: info.CFBundleDisplayName === '余记账本',
  minimumOS: info.MinimumOSVersion === '17.0',
  devicePlatform: info.CFBundleSupportedPlatforms?.includes('iPhoneOS') === true,
  cloudEnabled: info.YujiCloudKitEnabled === 'YES' || info.YujiCloudKitEnabled === true,
  cloudEnvironment: info.YujiCloudKitEnvironment === 'Production',
  cloudContainer: info.YujiCloudKitContainer === 'iCloud.com.dmlayman.yuji',
  sharing: info.CKSharingSupported === true,
  noFixture: !fs.existsSync(path.join(app, 'stats-500.json')),
  noTestFlags: !markers.some(marker => binary.includes(Buffer.from(marker))),
  noSimulatedClients: !['SimulatedCloudTransport', 'IsolatedSupportClient'].some(name => symbols.includes(name)),
  noNativeTests: !fs.existsSync(path.join(app, 'PlugIns')) ||
    !fs.readdirSync(path.join(app, 'PlugIns')).some(name => name.endsWith('.xctest')),
  offlinePolicyMatchesSource: hash(path.join(app, 'PrivacyPolicy.md')) === hash('docs/privacy/PrivacyPolicy.md'),
  noTracking: privacy.NSPrivacyTracking === false,
};
const passed = Object.values(checks).every(Boolean);
console.log(JSON.stringify({ passed, scope: 'resources/configuration only; not signing or live acceptance',
  version: info.CFBundleShortVersionString, build: info.CFBundleVersion, checks }, null, 2));
if (!passed) process.exitCode = 1;
