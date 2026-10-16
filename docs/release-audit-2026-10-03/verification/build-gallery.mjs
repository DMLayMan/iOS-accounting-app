// Dated audit artifact generator. Run from the repository root after exporting xcresult attachments.
// Original PNG files are copied unchanged. Never substitutes historical screenshots.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const root = 'evidence/release-audit-20261003';
const output = path.join(root, 'gallery');
const runs = [
  ['pro27', 'iPhone 18 Pro · iOS 27.0', 'pro27-attachments'],
  ['se26', 'iPhone SE 3 · iOS 26.5', 'se26-attachments'],
  ['supplement-v3', 'iPhone 17 Pro · iOS 26.5', 'supplement-v3-attachments'],
  ['supplement-v4', 'iPhone 17 Pro · iOS 26.5', 'supplement-v4-attachments'],
  ['pro27-theme-recheck', 'iPhone 18 Pro · iOS 27.0', 'pro27-theme-recheck-attachments'],
  ['pro27-category-capture', 'iPhone 18 Pro · iOS 27.0', 'category-capture-attachments'],
];
const titleSource = fs.readFileSync('scripts/build-current-gallery.mjs', 'utf8').split('const candidates')[0];
const titles = new Map([...titleSource.matchAll(/'([^']+)':'([^']+)'/g)].map(m => [m[1], m[2]]));
for (const [key, value] of Object.entries({
  'release-01-refund-save': '实际保存退款 · 主题问题',
  'release-02-transfer-save': '实际保存转账',
  'release-03-balanced-after-relaunch': '重启后余额对账',
  'release-04-backup-system-share': '备份系统分享',
  'release-05-csv-system-share': 'CSV 系统分享',
  'release-06-system-file-picker': '系统文件选择与取消',
  'release-07-long-account-name': 'P1 · 长账户名撑宽记账页',
  '04-budget-category-picker': '预算分类选择 · 支持一级与二级',
})) titles.set(key, value);

fs.mkdirSync(output, {recursive: true});
const rows = [];
for (const [run, device, folder] of runs) {
  const directory = path.join(root, folder);
  const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'manifest.json'), 'utf8'));
  for (const test of manifest) for (const attachment of test.attachments) {
    if (!attachment.exportedFileName.endsWith('.png')) continue;
    const stem = attachment.suggestedHumanReadableName.split(/_\d+_/)[0];
    if (!/^(?:\d{2}-|release-\d{2}-)/.test(stem)) continue;
    // Newer share screenshots wait for visible controls rather than catching the presentation transition.
    if (run === 'supplement-v3' && /release-0[456]-/.test(stem)) continue;
    const source = path.join(directory, attachment.exportedFileName);
    const sha256 = crypto.createHash('sha256').update(fs.readFileSync(source)).digest('hex');
    const file = `${run}-${stem}-${sha256.slice(0, 8)}.png`;
    fs.copyFileSync(source, path.join(output, file));
    rows.push({run, device, stem, title: titles.get(stem) ?? stem, file, sha256,
      test: test.testIdentifier, source,
      capturedAt: new Date(attachment.timestamp * 1000).toISOString(),
      knownFailure: stem === 'release-07-long-account-name'});
  }
}
rows.sort((a, b) => Number(b.knownFailure) - Number(a.knownFailure)
  || a.test.localeCompare(b.test) || a.stem.localeCompare(b.stem) || a.run.localeCompare(b.run));
const report = {generatedAt: new Date().toISOString(), implementationCommit: '58aed2d526844739e13cdf2795800f83e869681d', screenshots: rows};
fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify(report, null, 2) + '\n');
fs.writeFileSync('docs/release-audit-2026-10-03/verification/screenshots.json', JSON.stringify(report, null, 2) + '\n');
const escape = value => String(value).replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
fs.writeFileSync(path.join(output, 'index.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>余记 · 2026-10-03 发布前原生审查</title><style>
*{box-sizing:border-box}body{margin:0;padding:24px;background:#f2f4f2;color:#20342b;font:15px/1.6 system-ui}header{max-width:1500px;margin:auto}h1{font-size:28px;margin:0}p{margin:8px 0}a{color:#286549}label{margin-right:12px}input,select{font:inherit;border:1px solid #aab8af;border-radius:8px;padding:9px;background:white;color:#20342b}input{width:min(340px,100%)}main{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px;max-width:1500px;margin:22px auto}figure{margin:0;padding:12px;background:white;border-radius:12px;align-self:start}figure[data-failure="true"]{outline:2px solid #a94635}img{display:block;width:100%;height:auto}figcaption{font-size:13px;padding-top:8px;overflow-wrap:anywhere}small{color:#58695f}.note{color:#984030}figure[hidden]{display:none}@media(max-width:900px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:480px){main{grid-template-columns:1fr}}
</style><header><h1>余记 · 发布前原生审查</h1><p>2026-10-03 当前原生回归截图；核心功能内测版，尚未达到发布候选版。全部使用隔离合成数据。点击原图放大。</p><p class="note">红框为已确认失败：长账户名撑宽记账页。正常流程通过不代表所有边界或 App Store 已验收。</p><p><a href="../../../docs/release-audit-2026-10-03/README.md">审查报告</a> · <a href="../../../docs/release-audit-2026-10-03/coverage.md">全部功能/页面矩阵</a> · <a href="manifest.json">测试来源与原图 SHA-256</a></p>
<label>机型 <select id="device"><option value="">全部</option value="pro27">18 Pro / iOS 27</option value="se26">SE 3 / iOS 26.5</option value="supplement">17 Pro / 补充边界</option></select></label><label>筛选 <input id="query" placeholder="页面名称或测试组，例如：预算、Theme、dark"></label><span id="count"></span></header><main>
${rows.map(c => `<figure data-run="${c.run}" data-search="${escape(c.title + ' ' + c.test + ' ' + c.stem)}" data-failure="${c.knownFailure}"><a href="${c.file}"><img loading="lazy" src="${c.file}" alt="${escape(c.title)}"></a><figcaption><strong>${escape(c.title)}</strong><br>${escape(c.device)}<br><small>${escape(c.test)}</small></figcaption></figure>`).join('\n')}
</main><script>const device=document.querySelector('#device'),query=document.querySelector('#query');function filter(){let count=0;for(const f of document.querySelectorAll('figure')){f.hidden=!(f.dataset.run.startsWith(device.value)&&f.dataset.search.toLowerCase().includes(query.value.trim().toLowerCase()));if(!f.hidden)count++}document.querySelector('#count').textContent=count+' 张'}device.addEventListener('change',filter);query.addEventListener('input',filter);filter()</script></html>`);
console.log(JSON.stringify({screenshots: rows.length, output}));
