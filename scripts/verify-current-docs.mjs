import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const files = ['README.md','PRODUCT.md','DESIGN.md','docs/README.md','docs/PRD.md','docs/UI-SPEC.md','docs/ARCHITECTURE.md','docs/regression-2026-09-11.md'];
const errors = [];
let checkedLinks = 0;
for (const file of files) {
  const text = fs.readFileSync(file,'utf8');
  for (const match of text.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
    const target = match[1].split('#')[0];
    if (!target || /^[a-z]+:/.test(target)) continue;
    checkedLinks++;
    if (!fs.existsSync(path.resolve(path.dirname(file),target))) errors.push(`${file}: missing ${target}`);
  }
}
const root = 'docs/assets/current';
const manifest = JSON.parse(fs.readFileSync(path.join(root,'manifest.json'),'utf8'));
const html = fs.readFileSync(path.join(root,'index.html'),'utf8');
for (const item of manifest.screenshots) {
  if (path.basename(item.file) !== item.file) throw new Error('Screenshot paths must be local basenames.');
  const data = fs.readFileSync(path.join(root,item.file));
  if (crypto.createHash('sha256').update(data).digest('hex') !== item.sha256) errors.push(`Screenshot hash: ${item.file}`);
  if (!html.includes(`src="${item.file}"`)) errors.push(`Gallery missing ${item.file}`);
}
for (const marker of ['账本','流水','统计','分类','预算','主题','恢复']) {
  if (!manifest.screenshots.some(s=>s.title.includes(marker))) errors.push(`Missing page family: ${marker}`);
}
if (!manifest.screenshots.some(s=>s.device.includes('SE'))) errors.push('Missing compact device evidence');
const report = {passed:!errors.length,documents:files.length,checkedLinks,screenshots:manifest.screenshots.length,errors};
console.log(JSON.stringify(report,null,2));
if (errors.length) process.exitCode = 1;
