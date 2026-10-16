import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { verifyPlaybook } from './verify-ios-playbook.mjs';

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ios-playbook-check-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const write = (name, content) => {
    fs.mkdirSync(path.dirname(path.join(root, name)), { recursive: true });
    fs.writeFileSync(path.join(root, name), content);
  };
  const bundle = 'skills/indie-ios-product';
  const source = { 'SKILL.md': '[Guide](references/guide.md)\n', 'references/guide.md': '# Guide\n' };
  for (const [name, content] of Object.entries(source)) write(`${bundle}/${name}`, content);
  write('AGENTS.md', '[Docs](docs/indie-ios/README.md)\n');
  write('docs/README.md', '[Guide](indie-ios/README.md)\n');
  write('docs/indie-ios/README.md', '[Skill](../../skills/indie-ios-product/SKILL.md)\n');
  write('docs/indie-ios/skill-manifest.json', JSON.stringify({ files: Object.entries(source).map(([file, text]) => ({
    file, sha256: crypto.createHash('sha256').update(text).digest('hex')
  })) }));
  const installed = path.join(root, 'installed');
  fs.cpSync(path.join(root, bundle), installed, { recursive: true });
  return { root, write, installed, bundle };
}

test('valid package passes both portable and installed checks without rewriting it', t => {
  const f = fixture(t);
  const before = fs.readFileSync(path.join(f.root, 'docs/indie-ios/skill-manifest.json'));
  assert.equal(verifyPlaybook(f.root).passed, true);
  const result = verifyPlaybook(f.root, f.installed);
  assert.equal(result.passed, true);
  assert.equal(result.installedRequested, true);
  assert.deepEqual(fs.readFileSync(path.join(f.root, 'docs/indie-ios/skill-manifest.json')), before);
});

test('stale source hash fails and is not silently refreshed', t => {
  const f = fixture(t);
  f.write(`${f.bundle}/references/guide.md`, '# Changed\n');
  assert.equal(verifyPlaybook(f.root).passed, false);
  assert.equal(verifyPlaybook(f.root).passed, false);
});

test('a broken documentation link fails even when skill hashes match', t => {
  const f = fixture(t);
  f.write('docs/indie-ios/README.md', '[Missing](missing.md)\n');
  const r = verifyPlaybook(f.root);
  assert.equal(r.checks.find(x => x.name === 'source manifest').passed, true);
  assert.equal(r.checks.find(x => x.name === 'references').passed, false);
});

test('extra and missing skill files require an updated inventory', t => {
  const f = fixture(t);
  f.write(`${f.bundle}/extra.md`, '# Extra\n');
  assert.equal(verifyPlaybook(f.root).passed, false);
  fs.unlinkSync(path.join(f.root, f.bundle, 'extra.md'));
  fs.unlinkSync(path.join(f.root, f.bundle, 'references/guide.md'));
  assert.equal(verifyPlaybook(f.root).passed, false);
});

test('an installed copy that drifted or is missing never reports parity', t => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.installed, 'SKILL.md'), '# Local modification\n');
  assert.equal(verifyPlaybook(f.root, f.installed).passed, false);
  assert.equal(verifyPlaybook(f.root, path.join(f.root, 'not-installed')).passed, false);
});

test('skill references cannot depend on repository files outside the package', t => {
  const f = fixture(t);
  f.write(`${f.bundle}/SKILL.md`, '[Outside](../../AGENTS.md)\n');
  assert.equal(verifyPlaybook(f.root).checks.find(x => x.name === 'references').passed, false);
});

test('symlinks cannot smuggle an external dependency into the skill', t => {
  const f = fixture(t);
  const guide = path.join(f.root, f.bundle, 'references/guide.md');
  fs.unlinkSync(guide);
  fs.symlinkSync(path.join(f.root, 'AGENTS.md'), guide);
  assert.equal(verifyPlaybook(f.root).passed, false);
});
