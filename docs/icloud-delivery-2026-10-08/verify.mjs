// Artifact integrity and coverage checks; not real-cloud or App Store acceptance.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const root = 'docs/icloud-delivery-2026-10-08';
const read = file=>fs.readFileSync(file,'utf8');
const json = file=>JSON.parse(read(file));
const hash = bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const errors = [];
const documents = ['README.md','PRODUCT.md','DESIGN.md','docs/README.md','docs/PRD.md','docs/UI-SPEC.md','docs/ARCHITECTURE.md','docs/privacy/PrivacyPolicy.md','docs/indie-ios/session-lessons.md',`${root}/README.md`,`${root}/configuration.md`,`${root}/real-cloud-acceptance.md`];
for (const file of documents) for (const m of read(file).matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
  const target = m[1].split('#')[0];
  if (target && !/^[a-z]+:/.test(target) && !fs.existsSync(path.resolve(path.dirname(file),target))) errors.push(`Missing link: ${file} -> ${target}`);
}
const core = json(`${root}/verification/core.json`);
if (!core.total || core.suites.some(s=>s.failures)) errors.push('Incomplete portable tests');
const native = json(`${root}/verification/native-coverage.json`);
for (const c of native.coverage) if (c.missing.length || c.failed.length || c.passed!==c.expected) errors.push(`Incomplete native coverage: ${c.family}`);
// Full batch predates the global alert timing repair. Final cloud reruns must have no SwiftUI warning.
const finalRuns = native.runs.filter(r=>r.run.startsWith('cloud-') && r.run.endsWith('verified'));
if (new Set(finalRuns.map(r=>r.family)).size!==2 || finalRuns.some(r=>r.result!=='Passed' || r.runtimeWarnings.length)) errors.push('Final cloud UI/warning check incomplete');
const gallery = json(`${root}/gallery/manifest.json`), html = read(`${root}/gallery/index.html`);
for (const s of gallery.screenshots) {
  if (path.basename(s.file)!==s.file || hash(fs.readFileSync(`${root}/gallery/${s.file}`))!==s.sha256 || !html.includes(`src="${s.file}"`)) errors.push(`Screenshot changed or absent: ${s.file}`);
}
for (const stem of ['owner-synced','paused-relaunch','readonly','conflict-comparison','conflict-resolved','offline','revoked','signed-out-accessibility','dark-large','local-copy-after-leave','independent-cloud-copy']) if (!gallery.screenshots.some(s=>s.stem.includes(stem))) errors.push(`Missing UI state: ${stem}`);
const releases = json(`${root}/verification/releases.json`);
if (releases.runs.length!==2 || releases.runs.some(r=>!r.archiveSucceeded || r.fakeSymbols || r.fixturePresent || !r.policyMatchesSource || r.environment!=='Production')) errors.push('Release verification incomplete');
const sources = json(`${root}/verification/source-fingerprints.json`);
for (const [file,digest] of Object.entries(sources.files)) if (hash(fs.readFileSync(file))!==digest) errors.push(`Source changed after verification: ${file}`);
console.log(JSON.stringify({passed:!errors.length,portable:core.total,perDevice:native.coverage.map(c=>({device:c.family,tests:c.passed})),nativeScreenshots:gallery.screenshots.length,scope:'current artifacts, local tests and unsigned archives; real CloudKit remains pending',errors},null,2));
if (errors.length) process.exitCode = 1;
