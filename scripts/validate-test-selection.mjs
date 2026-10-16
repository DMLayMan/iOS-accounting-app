// Xcode silently accepts a misspelled only-testing filter. Reject it before launch.
import fs from 'node:fs';
import path from 'node:path';
const targets = new Map();
function scan(directory, classes) {
  for (const entry of fs.readdirSync(directory,{withFileTypes:true})) {
    const file = path.join(directory,entry.name);
    if (entry.isDirectory()) { scan(file,classes); continue; }
    if (!file.endsWith('.swift')) continue;
    let owner;
    for (const line of fs.readFileSync(file,'utf8').split('\n')) {
      const type = line.match(/(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase/);
      if (type) { owner=type[1]; classes.set(owner,new Set()); }
      const test = line.match(/func\s+(test\w+)\s*\(/);
      if (owner && test) classes.get(owner).add(test[1]);
    }
  }
}
for (const name of ['YujiTests','YujiUITests']) {
  const classes = new Map(); scan(`ios-app/${name}`,classes); targets.set(name,classes);
}
const args=process.argv.slice(2), errors=[];
let selections=0;
for (let i=0;i<args.length;i++) {
  const match=args[i].match(/^-(?:only|skip)-testing(?::(.+))?$/);
  if (!match) continue;
  const value=match[1] ?? args[++i]; selections++;
  const parts=(value ?? '').split('/');
  const [target,owner,test]=parts;
  if (parts.length>3 || !targets.has(target) || owner && !targets.get(target).has(owner)
      || test && !targets.get(target)?.get(owner)?.has(test)) errors.push(`Unknown test selection: ${value}`);
}
if (errors.length) { console.error(errors.join('\n')); process.exitCode=2; }
else console.log(`Validated ${selections} test selections against current native test sources.`);
