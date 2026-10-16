// Run from the repository root with completed native run names, oldest first.
// Uses Xcode result bundles and copies original pixels; never reconstructs screenshots.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
const output = 'docs/icloud-delivery-2026-10-08';
const evidence = 'evidence/icloud-20261008';
const runs = process.argv.slice(2);
if (!runs.length) throw new Error('Specify completed run names.');
const json = (file, value) => fs.writeFileSync(file, JSON.stringify(value,null,2)+'\n');
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = file => fs.readFileSync(file,'utf8');
function files(dir) {
  return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(path.join(dir,e.name)):[path.join(dir,e.name)]);
}
function cases(dir, module) {
  const sources = files(dir).filter(f=>f.endsWith('.swift')).map(read);
  const names = new Set(sources.flatMap(source=>[...source.matchAll(/class\s+(\w+)\s*:\s*XCTestCase/g)].map(m=>m[1])));
  return sources.flatMap(source=>{
    let current; const result = [];
    for (const m of source.matchAll(/class\s+(\w+)\s*:\s*XCTestCase|extension\s+(\w+)|func\s+(test\w+)\s*\(/g)) {
      if (m[1] || m[2]) current = names.has(m[1] ?? m[2]) ? (m[1] ?? m[2]) : undefined;
      else if (current) result.push(`${module}.${current}/${m[3]}()`);
    }
    return result;
  }).sort();
}
const expected = [...cases('ios-app/YujiTests','YujiTests'),...cases('ios-app/YujiUITests','YujiUITests')];
const latest = new Map(), captured = new Map(), raw = [];
fs.mkdirSync(`${output}/verification`,{recursive:true});
fs.mkdirSync(`${output}/gallery`,{recursive:true});
for (const run of runs) {
  const folder = `${evidence}/${run}`, log = read(`${folder}/native.log`);
  if (!/\*\* TEST EXECUTE (?:SUCCEEDED|FAILED) \*\*/.test(log)) throw new Error(`Incomplete run: ${run}`);
  const summary = JSON.parse(execFileSync('xcrun',['xcresulttool','get','test-results','summary','--path',`${folder}/results.xcresult`,'--compact'],{encoding:'utf8'}));
  json(`${output}/verification/${run}.json`,summary);
  const device = summary.devicesAndConfigurations[0].device;
  const family = device.modelName.includes('SE') ? 'se' : device.modelName.includes('18 Pro') ? 'pro' : 'pro17';
  const results = new Map();
  for (const m of log.matchAll(/Test Case '-\[((?:YujiTests|YujiUITests)\.\w+) (test\w+)\]' (passed|failed)/g)) {
    const id = `${m[1]}/${m[2]}()`; results.set(id,m[3]); latest.set(`${family}:${id}`,{family,id,result:m[3],run});
  }
  raw.push({run,family,device,result:summary.result,counts:{passed:summary.passedTests,failed:summary.failedTests,skipped:summary.skippedTests},runtimeWarnings:summary.runtimeWarnings});
  const attachments = `${folder}/attachments-final`;
  if (!fs.existsSync(`${attachments}/manifest.json`)) execFileSync('xcrun',['xcresulttool','export','attachments','--path',`${folder}/results.xcresult`,'--output-path',attachments],{stdio:'pipe'});
  for (const test of JSON.parse(read(`${attachments}/manifest.json`))) {
    if (results.get(`YujiUITests.${test.testIdentifier}`) !== 'passed') continue;
    for (const a of test.attachments) {
      if (!a.exportedFileName.endsWith('.png')) continue;
      const stem = a.suggestedHumanReadableName.split(/_\d+_/)[0];
      if (!stem.startsWith('cloud-')) continue;
      const source = `${attachments}/${a.exportedFileName}`, bytes = fs.readFileSync(source), sha256 = hash(bytes);
      captured.set(`${family}:${stem}`,{run,device:`${device.modelName} · iOS ${device.osVersion}`,test:test.testIdentifier,stem,source,sha256,capturedAt:new Date(a.timestamp*1000).toISOString(),file:`${family}-${stem}-${sha256.slice(0,8)}.png`});
    }
  }
}
const coverage = ['pro','se'].map(family=>{
  const rows = expected.map(id=>latest.get(`${family}:${id}`));
  return {family,expected:expected.length,passed:rows.filter(r=>r?.result==='passed').length,missing:expected.filter((_,i)=>!rows[i]),failed:rows.filter(r=>r?.result==='failed'),cases:rows.filter(Boolean)};
});
json(`${output}/verification/native-coverage.json`,{scope:'latest result per device and test identity; hosted and portable state tests overlap',runs:raw,coverage});
const log = read(`${evidence}/core-verified.log`);
const suites = [...log.matchAll(/Test Suite '(\w+\.xctest)' passed[^\n]*\n\s*Executed (\d+) tests, with (\d+) failures/g)].map(m=>({suite:m[1],tests:Number(m[2]),failures:Number(m[3])}));
if (suites.length !== 2) throw new Error('Both portable test targets must complete.');
json(`${output}/verification/core.json`,{source:`${evidence}/core-verified.log`,suites,total:suites.reduce((n,s)=>n+s.tests,0)});
const screenshots = [...captured.values()].sort((a,b)=>a.stem.localeCompare(b.stem)||a.device.localeCompare(b.device));
for (const s of screenshots) fs.copyFileSync(s.source,`${output}/gallery/${s.file}`);
json(`${output}/gallery/manifest.json`,{scope:'isolated simulated cloud, native original pixels; not real CloudKit evidence',screenshots});
const escape = value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
fs.writeFileSync(`${output}/gallery/index.html`,`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>余记 · iCloud 原生自测</title><style>body{font:15px/1.6 system-ui;background:#f4f5f4;color:#26352e;margin:24px}header,main{max-width:1120px;margin:auto}main{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px;margin-top:24px}figure{background:white;padding:12px;border-radius:12px;margin:0;align-self:start}img{width:100%;display:block}figcaption{font-size:13px;overflow-wrap:anywhere}a{color:#286549}@media(max-width:700px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:420px){main{grid-template-columns:1fr}}</style><header><h1>iCloud 与多人账本 · 原生表现</h1><p>隔离模拟云端，不连接真实 iCloud。小屏、默认字号、深色与最大字号；点击原图放大。每张对应已通过的测试，未重绘。</p><a href="../README.md">交付与验收边界</a> · <a href="manifest.json">原图来源与校验</a></header><main>${screenshots.map(s=>`<figure><a href="${s.file}"><img loading="lazy" src="${s.file}" alt="${escape(s.stem)}"></a><figcaption>${escape(s.stem)}<br>${escape(s.device)}<br>${escape(s.test)} · ${escape(s.run)}</figcaption></figure>`).join('\n')}</main></html>`);
const frozen = [...files('Sources'),...files('Tests'),...files('ios-app/Yuji'),...files('ios-app/YujiTests'),...files('ios-app/YujiUITests'), 'Package.swift','ios-app/project.yml','docs/privacy/PrivacyPolicy.md'];
json(`${output}/verification/source-fingerprints.json`,{scope:'current source after final repairs; full-v8 is the broad UI baseline, then v14 reruns all hosted tests, cloud UI and the background draft case after alert timing, same-book account isolation, restore-copy and active-ledger preservation fixes',files:Object.fromEntries(frozen.map(file=>[file,hash(fs.readFileSync(file))]))});
console.log(JSON.stringify({portable:suites,coverage:coverage.map(({family,expected,passed,missing,failed})=>({family,expected,passed,missing,failed})),screenshots:screenshots.length},null,2));
