// Read-only checks for inline Markdown links, package inventory and SHA-256.
// This does not evaluate design quality or replace the skill YAML validator.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const within = (root, target) => {
  const relative = path.relative(root, target);
  return relative === '' || (!path.isAbsolute(relative) && relative !== '..' && !relative.startsWith(`..${path.sep}`));
};

function files(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`Unexpected symlink: ${file}`);
    return entry.isDirectory() ? files(file) : [file];
  }).sort();
}

const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

export function verifyPlaybook(repositoryRoot, installedDirectory) {
  const root = fs.realpathSync(repositoryRoot);
  const bundle = path.join(root, 'skills/indie-ios-product');
  const docs = path.join(root, 'docs/indie-ios');
  const checks = [];
  const check = (name, action) => {
    try { checks.push({ name, passed: true, ...action() }); }
    catch (error) { checks.push({ name, passed: false, error: error.message }); }
  };

  check('references', () => {
    const markdown = [...files(bundle), ...files(docs), path.join(root, 'AGENTS.md'), path.join(root, 'docs/README.md')]
      .filter(file => file.endsWith('.md'));
    let links = 0;
    for (const file of markdown) {
      // Code examples are examples, not document navigation.
      const content = fs.readFileSync(file, 'utf8').replace(/^```[^\n]*\n[\s\S]*?^```\s*$/gm, '');
      for (const [, target] of content.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
        if (/^[a-z][a-z\d+.-]*:/i.test(target) || target.startsWith('#')) continue;
        const relative = target.split('#')[0];
        const resolved = path.resolve(path.dirname(file), relative);
        const boundary = within(bundle, file) ? bundle : root;
        if (!within(boundary, resolved)) throw new Error(`Reference outside package: ${file} -> ${target}`);
        if (!fs.existsSync(resolved)) throw new Error(`Missing reference: ${file} -> ${target}`);
        if (!within(boundary, fs.realpathSync(resolved))) throw new Error(`Reference symlink outside package: ${target}`);
        links++;
      }
    }
    return { documents: markdown.length, links };
  });

  check('source manifest', () => {
    const manifest = JSON.parse(fs.readFileSync(path.join(docs, 'skill-manifest.json'), 'utf8'));
    const inventory = files(bundle).map(file => path.relative(bundle, file));
    const expected = manifest.files.map(record => record.file).sort();
    if (new Set(expected).size !== expected.length) throw new Error('Duplicate manifest paths');
    if (JSON.stringify(inventory) !== JSON.stringify(expected)) throw new Error('Manifest file inventory differs from source');
    for (const record of manifest.files) {
      const file = path.resolve(bundle, record.file);
      if (!within(bundle, file)) throw new Error('Manifest path outside package');
      if (hash(file) !== record.sha256) throw new Error(`Source hash differs: ${record.file}`);
    }
    return { files: inventory.length };
  });

  if (installedDirectory) check('installed parity', () => {
    const installed = fs.realpathSync(installedDirectory);
    const sourceFiles = files(bundle).map(file => path.relative(bundle, file));
    const installedFiles = files(installed).map(file => path.relative(installed, file));
    if (JSON.stringify(sourceFiles) !== JSON.stringify(installedFiles)) throw new Error('Installed file inventory differs');
    for (const file of sourceFiles) {
      if (hash(path.join(bundle, file)) !== hash(path.join(installed, file))) throw new Error(`Installed hash differs: ${file}`);
    }
    return { files: sourceFiles.length };
  });

  return { checkedAt: new Date().toISOString(), passed: checks.every(check => check.passed),
    installedRequested: Boolean(installedDirectory), checks };
}

if (process.argv[1] && path.resolve(process.argv[1]) === scriptPath) {
  const args = process.argv.slice(2);
  if (args.length && (args.length !== 2 || args[0] !== '--installed')) {
    process.stderr.write('Usage: node scripts/verify-ios-playbook.mjs [--installed SKILL_DIRECTORY]\n');
    process.exitCode = 2;
  } else {
    const result = verifyPlaybook(path.resolve(path.dirname(scriptPath), '..'), args[1]);
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    process.exitCode = result.passed ? 0 : 1;
  }
}
