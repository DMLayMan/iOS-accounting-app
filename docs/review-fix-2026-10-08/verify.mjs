// Portable artifact checks, not a replacement for XCTest or human visual review.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const root = 'docs/review-fix-2026-10-08';
const errors = [];
const documents = ['README.md','AGENTS.md','docs/README.md','docs/PRD.md','docs/UI-SPEC.md','docs/ARCHITECTURE.md',
  `${root}/README.md`,`${root}/coverage.md`,`${root}/visual-review.md`,'docs/indie-ios/session-lessons.md'];
let links = 0;
for (const file of documents) {
  for (const m of fs.readFileSync(file,'utf8').matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
    const target = m[1].split('#')[0];
    if (!target || /^[a-z]+:/.test(target)) continue;
    links++;
    if (!fs.existsSync(path.resolve(path.dirname(file),target))) errors.push(`Missing link: ${file} → ${target}`);
  }
}
const gallery = path.join(root,'gallery');
const manifest = JSON.parse(fs.readFileSync(path.join(gallery,'manifest.json'),'utf8'));
const html = fs.readFileSync(path.join(gallery,'index.html'),'utf8');
for (const r of manifest.screenshots) {
  if (path.basename(r.file) !== r.file) throw new Error('Image must use a local filename.');
  const bytes = fs.readFileSync(path.join(gallery,r.file));
  if (crypto.createHash('sha256').update(bytes).digest('hex') !== r.sha256) errors.push(`Image hash: ${r.file}`);
  if (!html.includes(`src="${r.file}"`)) errors.push(`Image absent from gallery: ${r.file}`);
}
for (const device of ['SE 3','18 Pro']) {
  if (!manifest.screenshots.some(r=>r.device.includes(device))) errors.push(`Missing device: ${device}`);
}
for (const device of ['pro27','se26']) {
  const ui = JSON.parse(fs.readFileSync(path.join(root,'verification',`ui-${device}.json`),'utf8'));
  if (ui.missing.length || ui.failed.length || ui.passed !== ui.expected) errors.push(`Incomplete UI coverage: ${device}`);
}
const core = JSON.parse(fs.readFileSync(path.join(root,'verification','core.json'),'utf8'));
if (!core.total || core.warnings || core.suites.some(r=>r.failures)) errors.push('Portable tests incomplete or unexpected warnings.');
const native = JSON.parse(fs.readFileSync(path.join(root,'verification','native.json'),'utf8'));
if (native.runs.some(r=>r.unitPassed!==20 || r.unitFailed.length || r.invalidFrameWarnings)) errors.push('Native unit/runtime verification incomplete.');
if (native.uiRuntimeRuns.some(r=>!r.completed || r.invalidFrameWarnings)) errors.push('Final UI runtime verification incomplete.');
const release = JSON.parse(fs.readFileSync(path.join(root,'verification','release.json'),'utf8'));
if (!release.archiveSucceeded || release.configuration!=='Release' || !release.icons?.CFBundlePrimaryIcon
    || !release.policyBundled || !release.policyMatchesSource || release.fixturePresent
    || !release.privacy.NSPrivacyAccessedAPITypes.some(r=>r.NSPrivacyAccessedAPIType==='NSPrivacyAccessedAPICategoryFileTimestamp' && r.NSPrivacyAccessedAPITypeReasons.includes('C617.1')))
  errors.push('Release resource verification incomplete.');
const sources = JSON.parse(fs.readFileSync(path.join(root,'verification','source-fingerprints.json'),'utf8'));
for (const [file,expected] of Object.entries(sources.files)) {
  const digest = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  if (digest !== expected) errors.push(`Source changed after verification: ${file}`);
}
const result = {passed:errors.length===0,scope:'document links, native-original hashes, portable/native/UI result coverage, archive resource facts and frozen source fingerprints',
  documents:documents.length,links,screenshots:manifest.screenshots.length,errors};
console.log(JSON.stringify(result,null,2));
if (errors.length) process.exitCode=1;
