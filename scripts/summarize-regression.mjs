// Merge ordered test runs by case identity. Later results supersede earlier ones.
// Usage: node scripts/summarize-regression.mjs LOG [...]
import fs from 'node:fs';
import path from 'node:path';
function sourceTests(directory) {
  const expected = new Set();
  for (const name of fs.readdirSync(directory)) {
    const file = path.join(directory,name);
    if (!file.endsWith('.swift')) continue;
    const text = fs.readFileSync(file,'utf8');
    let owner;
    for (const line of text.split('\n')) {
      const type = line.match(/(?:final )?class (\w+)\s*:\s*XCTestCase/);
      if (type) owner = type[1];
      const test = line.match(/func (test\w+)\(/);
      if (owner && test) expected.add(owner + '.' + test[1]);
    }
  }
  return expected;
}
const expected = sourceTests('ios-app/YujiUITests');
const cases = new Map();
for (const log of process.argv.slice(2)) {
  const text = fs.readFileSync(log,'utf8');
  for (const match of text.matchAll(/Test Case '-\[YujiUITests\.(\w+) (\w+)\]' (passed|failed) \(([\d.]+) seconds\)/g)) {
    cases.set(match[1]+'.'+match[2],{status:match[3],seconds:Number(match[4]),log});
  }
}
const missing = [...expected].filter(id=>!cases.has(id));
const failed = [...cases].filter(([id,r])=>expected.has(id)&&r.status !== 'passed').map(([id])=>id);
console.log(JSON.stringify({expected:expected.size,passed:[...expected].filter(id=>cases.get(id)?.status==='passed').length,missing,failed,
  cases:Object.fromEntries([...cases].sort(([a],[b])=>a.localeCompare(b)))},null,2));
if (missing.length || failed.length) process.exitCode = 1;
