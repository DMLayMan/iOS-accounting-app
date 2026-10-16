// Inspect unsigned Release archives; this does not prove provisioning or CloudKit access.
import fs from 'node:fs';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
const root = 'docs/icloud-delivery-2026-10-08';
const readPlist = file=>JSON.parse(execFileSync('plutil',['-convert','json','-o','-',file],{encoding:'utf8'}));
const hash = bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const policy = fs.readFileSync('docs/privacy/PrivacyPolicy.md');
const runs = ['release-local-final','release-cloud-final'].map(run=>{
  const folder = `evidence/icloud-20261008/${run}`, app = `${folder}/Yuji.xcarchive/Products/Applications/Yuji.app`;
  const info = readPlist(`${app}/Info.plist`), binary = fs.readFileSync(`${app}/Yuji`);
  const symbols = execFileSync('nm',[`${app}/Yuji`],{encoding:'utf8',maxBuffer:20_000_000});
  return {run,archiveSucceeded:fs.readFileSync(`${folder}/archive.log`,'utf8').includes('** ARCHIVE SUCCEEDED **'),unsigned:true,
    identifier:info.CFBundleIdentifier,enabled:info.YujiCloudKitEnabled,container:info.YujiCloudKitContainer,environment:info.YujiCloudKitEnvironment,
    sharingSupported:info.CKSharingSupported,minimumOS:info.MinimumOSVersion,icons:info.CFBundleIcons,
    fixturePresent:fs.existsSync(`${app}/stats-500.json`),fakeSymbols:symbols.includes('SimulatedCloudTransport'),
    testFlagsPresent:['YUJI_TEST_CLOUD_MODE','YUJI_STRESS_SESSION','YUJI_UI_TEST_SESSION'].filter(s=>binary.includes(Buffer.from(s))),
    policyMatchesSource:hash(policy)===hash(fs.readFileSync(`${app}/PrivacyPolicy.md`)),binarySHA256:hash(binary),privacy:readPlist(`${app}/PrivacyInfo.xcprivacy`)};
});
fs.writeFileSync(`${root}/verification/releases.json`,JSON.stringify({scope:'compile/resources; no signature, accounts, container registration or cloud requests',runs},null,2)+'\n');
const valid = runs.every(r=>r.archiveSucceeded && !r.fixturePresent && !r.fakeSymbols && !r.testFlagsPresent.length && r.policyMatchesSource && r.environment==='Production' && r.sharingSupported && r.enabled===(r.run.includes('local')?'NO':'YES'));
console.log(JSON.stringify({passed:valid,runs:runs.map(({run,enabled,archiveSucceeded,fakeSymbols,testFlagsPresent,policyMatchesSource})=>({run,enabled,archiveSucceeded,fakeSymbols,testFlagsPresent,policyMatchesSource}))},null,2));
if (!valid) process.exitCode=1;
