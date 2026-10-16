// Run from repo root after exporting attachments. Copies native originals unchanged.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const root = 'evidence/review-fix-20261008';
const output = 'docs/review-fix-2026-10-08/gallery';
const runs = process.argv.slice(2);
if (!runs.length) throw new Error('Provide ordered completed run names; newest last.');
const titleSource = fs.readFileSync('scripts/build-current-gallery.mjs', 'utf8').split('const candidates')[0];
const titles = new Map([...titleSource.matchAll(/'([^']+)':'([^']+)'/g)].map(m => [m[1], m[2]]));
for (const [k,v] of Object.entries({
  'release-01-refund-save':'实际保存退款', 'release-02-transfer-save':'实际保存转账',
  'release-03-balanced-after-relaunch':'重启后对账', 'release-04-backup-system-share':'备份系统分享',
  'release-05-csv-system-share':'CSV 系统分享', 'release-06-system-file-picker':'系统文件选择',
  'release-07-long-account-name':'长账户名布局', 'release-08-long-name-date-picker':'长名称仍能选择日期',
  'review-largest-type-long-account':'最大字号与长账户名', 'review-background-draft-restored':'后台草稿恢复',
  'review-background-reverted-draft':'撤回输入不复活旧草稿', 'review-account-amount-filter':'账户与金额筛选',
  'review-invalid-amount-range':'非法金额范围', 'review-recovery-points':'本地恢复点管理',
  'review-recovery-cleanup-confirm':'单项恢复点清理确认', 'review-no-usable-account':'无可用账户的解释',
  'review-privacy':'离线隐私说明', 'review-help':'帮助与反馈',
  '01-create-with-budgets':'创建账本与预算', '31-large-rule-editor':'大字号分类预算',
  '21-dark-rule-editor':'深色分类预算', '21-dark-refund':'深色退款',
})) titles.set(k,v);
const picked = new Map();
for (const run of runs) {
  const folder = path.join(root,run,'attachments');
  const manifest = JSON.parse(fs.readFileSync(path.join(folder,'manifest.json'),'utf8'));
  const log = fs.readFileSync(path.join(root,run,'native.log'),'utf8');
  const passed = new Set([...log.matchAll(/Test Case '-\[YujiUITests\.(\w+) (\w+)\]' passed/g)]
    .map(m => `${m[1]}/${m[2]}()`));
  const family = run.includes('se26') ? 'se26' : run.includes('17') ? 'pro17' : 'pro27';
  const device = family === 'se26' ? 'iPhone SE 3 · iOS 26.5' : family === 'pro17' ? 'iPhone 17 Pro · iOS 26.5' : 'iPhone 18 Pro · iOS 27.0';
  for (const test of manifest) {
    if (!passed.has(test.testIdentifier)) continue;
    for (const a of test.attachments) {
      const stem = a.suggestedHumanReadableName.split(/_\d+_/)[0];
      if (!a.exportedFileName.endsWith('.png') || !titles.has(stem)) continue;
      // Compact-device tour plus large-device changed states, not hundreds of duplicates.
      if (family === 'pro27' && !/^(?:release-|review-|.*(?:dark|theme|sheet-exit|create-with-budgets))/.test(stem)) continue;
      const source = path.join(folder,a.exportedFileName);
      const bytes = fs.readFileSync(source);
      const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
      picked.set(`${family}:${test.testIdentifier}:${stem}`, {run,device,test:test.testIdentifier,stem,title:titles.get(stem),
        source,sha256,capturedAt:new Date(a.timestamp*1000).toISOString(),file:`${family}-${stem}-${sha256.slice(0,8)}.png`});
    }
  }
}
fs.mkdirSync(output,{recursive:true});
const rows = [...picked.values()].sort((a,b)=>a.test.localeCompare(b.test)||a.stem.localeCompare(b.stem)||a.device.localeCompare(b.device));
for (const r of rows) fs.copyFileSync(r.source,path.join(output,r.file));
const record = {generatedAt:new Date().toISOString(),baselineCommit:'58aed2d526844739e13cdf2795800f83e869681d',scope:'representative native originals; isolated synthetic stores; newest passing capture by device/case/state',screenshots:rows};
fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(record,null,2)+'\n');
const escape = s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
fs.writeFileSync(path.join(output,'index.html'),`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>余记 · 全量复审原生图集</title>
<style>*{box-sizing:border-box}body{margin:24px;background:#f4f5f4;color:#20332c;font:15px/1.6 system-ui}header,main{max-width:1280px;margin:auto}h1{font-size:26px}a{color:#286549}input{font:inherit;padding:10px;border:1px solid #a9b8ae;border-radius:8px;width:min(100%,480px)}main{margin-top:24px;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:18px}figure{margin:0;padding:12px;background:white;border-radius:12px;align-self:start}img{width:100%;display:block}figcaption{padding-top:10px;font-size:13px;overflow-wrap:anywhere}small{color:#57675e}figure[hidden]{display:none}@media(max-width:850px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:430px){main{grid-template-columns:1fr}}</style>
<header><h1>余记 · 2026-10-08 复审原生表现</h1><p>代表原生截图，未经拼接或重绘。全部使用隔离合成数据。点击原图放大；自动化通过不代表所有主题/字号或真机已验收。</p><p><a href="../README.md">修复记录</a> · <a href="../coverage.md">功能与页面回收</a> · <a href="manifest.json">来源与原图 SHA-256</a></p><input id="q" aria-label="筛选截图" placeholder="筛选页面、设备、场景，例如：预算、深色、SE"><span id="count"></span></header><main>
${rows.map(r=>`<figure data-search="${escape(r.title+' '+r.device+' '+r.test+' '+r.stem)}"><a href="${r.file}"><img loading="lazy" src="${r.file}" alt="${escape(r.title)}"></a><figcaption><strong>${escape(r.title)}</strong><br>${escape(r.device)}<br><small>${escape(r.test)} · ${escape(r.run)}</small></figcaption></figure>`).join('\n')}
</main><script>const q=document.querySelector('#q');function filter(){let n=0;for(const f of document.querySelectorAll('figure')){f.hidden=!f.dataset.search.toLowerCase().includes(q.value.toLowerCase().trim());if(!f.hidden)n++}document.querySelector('#count').textContent=' '+n+' 张'}q.addEventListener('input',filter);filter()</script></html>`);
console.log(JSON.stringify({screenshots:rows.length,output}));
