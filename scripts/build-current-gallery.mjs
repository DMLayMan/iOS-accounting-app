// Curate original native screenshots; no image manipulation or synthetic UI.
// Usage: node scripts/build-current-gallery.mjs EXPORTED_ATTACHMENTS_DIR [...]
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const inputs = process.argv.slice(2);
if (!inputs.length) throw new Error('Provide xcresulttool attachment export directories.');
const titles = new Map(Object.entries({
  '01-ledger-cumulative':'账本累计', '02-ledger-accounts-summary':'账户余额汇总', '03-new-ledger-form':'创建账本',
  '05-switch-with-create':'切换与新建账本', '10-feed-current-month':'本月流水', '12-feed-leap-month':'历史闰月流水',
  '70-unified-statistics':'统计时间组件', '71-unified-feed':'流水同一时间组件', '02-month-picker':'月份面板',
  '11-year-statistics':'年度统计', '12-custom-range':'自定义时间', '13-future-range':'未来期间说明',
  '13-pie-selection-inline':'饼图同页筛选', '26-inline-leaf-transactions':'二级分类明细', '27-inline-comparison':'同期分析',
  '28-inline-base-period':'基期明细', '22-entry-amount-keypad':'记账金额键盘', '21-entry-keyboard-exclusive':'备注键盘互斥',
  '23-edit-cancel-inline':'编辑退出确认', '30-category-create-sheet':'新增分类图标表单', '32-category-created-selected':'创建后选中新分类',
  '01-entertainment-single-row':'少量二级分类单行', '03-native-long-press-reordered':'长按挪位', '05-search-locates-next-page':'分类查找定位',
  '02-rule-management':'分类预算管理', '10-two-overruns-collapsed':'超额默认折叠', '11-expanded-all-rules':'展开全部预算规则',
  '12-entry-related-budget-preview':'记账预算预览', '43-me':'我的', '44-accounts':'账户列表', '45-account-editor':'账户表单',
  '47-category-library':'分类管理', '48-ledgers':'账本管理', '49-trash':'最近删除', '50-data':'备份与导出',
  '54-transaction-detail':'单笔详情', '15-large-refund-prefill':'退款与剩余额度', '41-transfer':'转账表单',
  '62-backup-review':'恢复前确认', '63-backup-recovery-available':'替换前恢复点', '01-theme-settings':'主题设置',
  '11-custom-applied':'自定义主题', '20-dark-settings':'深色主题', '24-large-settings':'最大字号设置', '25-large-feed':'最大字号流水',
  '80-first-launch':'首次进入账本', '81-unreadable-recovery':'损坏数据恢复入口', '82-recovery-data':'恢复时禁用导出',
  '29-dark-large-text-exit':'大字号退出确认', '17-large-text-dark-drilldown':'大字号同页下钻',
  '83-refund-delete-undo':'退款删除与撤销', '84-theme-sheet-exit':'弹层主按钮主题一致', '85-empty-ledger-confirmation':'空账本删除确认'
}));
const candidates = new Map();
for (const directory of inputs) {
  const manifest = JSON.parse(fs.readFileSync(path.join(directory,'manifest.json'),'utf8'));
  for (const test of manifest) for (const attachment of test.attachments) {
    if (!attachment.exportedFileName.endsWith('.png')) continue;
    const stem = attachment.suggestedHumanReadableName.split(/_\d+_/)[0];
    if (!titles.has(stem)) continue;
    const device = attachment.deviceName.includes('Compact') ? 'se' : 'pro';
    const key = device + '-' + stem;
    const prior = candidates.get(key);
    if (!prior || attachment.timestamp > prior.timestamp) candidates.set(key, {
      ...attachment, stem, device, source: path.join(directory,attachment.exportedFileName), test: test.testIdentifier
    });
  }
}
const output = 'docs/assets/current';
fs.mkdirSync(output,{recursive:true});
const rows = [...candidates.values()].sort((a,b) => [...titles.keys()].indexOf(a.stem)-[...titles.keys()].indexOf(b.stem) || a.device.localeCompare(b.device));
const cards = rows.map(a => {
  const file = `${a.device}-${a.stem}.png`;
  const data = fs.readFileSync(a.source);
  fs.copyFileSync(a.source,path.join(output,file));
  return {file,title:titles.get(a.stem),device:a.device === 'se' ? 'iPhone SE 3' : 'iPhone 17 Pro', test:a.test,
    capturedAt:new Date(a.timestamp*1000).toISOString(), sha256:crypto.createHash('sha256').update(data).digest('hex')};
});
fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify({generatedAt:new Date().toISOString(),screenshots:cards},null,2)+'\n');
const escape = s => s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
fs.writeFileSync(path.join(output,'index.html'),`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>余记 · 当前原生页面</title>
<style>*{box-sizing:border-box}body{margin:0;padding:32px;background:#f4f5f3;color:#18241f;font:15px/1.65 system-ui}header{max-width:1080px;margin:auto}h1{margin:0;font-size:30px}p{color:#56645e}a{color:#367961}input{padding:12px 16px;font:inherit;border:1px solid #bac6bf;border-radius:10px;width:min(100%,420px)}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:24px;max-width:1440px;margin:28px auto}figure{margin:0;padding:12px;background:white;border-radius:16px;align-self:start}img{width:100%;height:auto;display:block;border-radius:8px}figcaption{padding:12px 3px 2px}small{color:#637269}figure[hidden]{display:none}@media(max-width:540px){body{padding:20px}main{grid-template-columns:1fr;max-width:360px}}</style>
<header><h1>余记 · 当前原生页面</h1><p>2026-09-11 回归截图，使用五年合成数据与隔离空账本。点击图片查看原图；每张图的测试来源与 SHA-256 见 <a href="manifest.json">清单</a>。</p><p><a href="../../PRD.md">PRD</a> · <a href="../../UI-SPEC.md">页面复刻清单</a> · <a href="../../ARCHITECTURE.md">架构</a> · <a href="../../regression-2026-09-11.md">回归结果</a></p><input aria-label="筛选页面或设备" placeholder="筛选页面或设备，例如：预算、SE、深色" id="filter"></header>
<main>${cards.map(c=>`<figure data-search="${escape(c.title+' '+c.device)}"><a href="${c.file}"><img loading="lazy" src="${c.file}" alt="${escape(c.title+' · '+c.device)}"></a><figcaption><strong>${escape(c.title)}</strong><br><small>${escape(c.device)}</small></figcaption></figure>`).join('')}</main>
<script>document.querySelector('#filter').addEventListener('input',e=>{const q=e.target.value.trim().toLowerCase();for(const f of document.querySelectorAll('figure'))f.hidden=!f.dataset.search.toLowerCase().includes(q)})</script></html>`);
console.log(JSON.stringify({screenshots:cards.length,output}));
