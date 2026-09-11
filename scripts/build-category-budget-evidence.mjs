import fs from 'node:fs';
import path from 'node:path';

const base = path.resolve('evidence/category-budget');
const titles = {
  '01-duplicate-rule-inline-error': ['manage', '重复范围就地提示'],
  '02-rule-management': ['manage', '添加、编辑、移除规则'],
  '03-no-category-rules': ['manage', '移除全部分类规则'],
  '10-two-overruns-collapsed': ['summary', '默认只展示两条超额'],
  '11-expanded-all-rules': ['summary', '同页展开全部规则'],
  '12-entry-related-budget-preview': ['summary', '仅预览本次分类相关预算'],
  '13-save-updates-category-budget': ['summary', '保存后统计同步刷新'],
  '20-dark-collapsed-budgets': ['adapt', '深色 · 超额提示'],
  '21-dark-rule-editor': ['adapt', '深色 · 编辑规则'],
  '30-large-collapsed-budgets': ['adapt', '最大字号 · 分类预算'],
  '31-large-rule-editor': ['adapt', '最大字号 · 输入金额'],
};
const screenshots = [];
for (const device of ['pro', 'compact']) {
  const chosen = new Map();
  for (const batch of ['first', 'confirm', 'fix-final', 'button-final']) {
    const source = `${device}-${batch}-shots`;
    const manifest = path.join(base, source, 'manifest.json');
    if (!fs.existsSync(manifest)) continue;
    for (const test of JSON.parse(fs.readFileSync(manifest))) {
      for (const item of test.attachments ?? []) {
        const name = item.suggestedHumanReadableName?.split('_0_')[0];
        if (titles[name] && !item.isAssociatedWithFailure) chosen.set(name, {source, item});
      }
    }
  }
  fs.mkdirSync(path.join(base, 'verified', device), {recursive: true});
  for (const [name, {source, item}] of [...chosen].sort(([a], [b]) => a.localeCompare(b))) {
    const file = `verified/${device}/${name}.png`;
    fs.copyFileSync(path.join(base, source, item.exportedFileName), path.join(base, file));
    screenshots.push({device, name, group: titles[name][0], title: titles[name][1], file, source, attachment: item.exportedFileName});
  }
}
fs.writeFileSync(path.join(base, 'screenshots.json'), JSON.stringify(screenshots, null, 2));
const cards = screenshots.map(s => `<figure data-device="${s.device}" data-group="${s.group}"><a href="${s.file}" target="_blank"><img src="${s.file}" alt="${s.title}" width="320" loading="lazy"></a><figcaption><strong>${s.title}</strong><span>${s.device === 'pro' ? 'iPhone 17 Pro' : 'iPhone SE 3'} · 原生截图</span></figcaption></figure>`).join('\n');
fs.writeFileSync(path.join(base, 'index.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>余记 · 分类预算</title>
<style>:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;color:#222b27;background:#f6f7f5;color-scheme:light}*{box-sizing:border-box}body{margin:0}header,main,footer{max-width:1100px;margin:auto;padding:28px 24px}h1{font-size:34px;line-height:1.3;margin:8px 0 16px}p{font-size:15px;line-height:1.8;color:#58635b;max-width:760px}a{color:#367961;text-underline-offset:4px}.links{display:flex;gap:24px;flex-wrap:wrap;font-size:14px}.controls{position:sticky;top:0;z-index:1;background:#f6f7f5;border-block:1px solid #dce2dc;padding:12px 24px}.inner{max-width:1052px;margin:auto;display:flex;align-items:center;gap:10px;flex-wrap:wrap}button,select{font:inherit;font-size:14px;min-height:44px;border:1px solid #d4ddd5;border-radius:24px;padding:0 16px;background:white;color:#39493f;cursor:pointer}button[aria-pressed=true]{background:#367961;color:white;border-color:#367961}button:focus-visible,select:focus-visible,a:focus-visible{outline:3px solid #87ae96;outline-offset:3px}#count{font-size:13px;color:#6e7972;margin-left:auto}main{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:28px 24px}figure{margin:0;min-width:0}figure[hidden]{display:none}figure a{display:block;border:1px solid #e0e5df;border-radius:22px;overflow:hidden;background:white}img{width:100%;height:auto;display:block}figcaption{padding:12px 2px;line-height:1.6}figcaption strong{display:block;font-size:15px;font-weight:600}figcaption span{font-size:12px;color:#7c857e}footer{border-top:1px solid #dce2dc;font-size:13px;line-height:1.8;color:#6e7972}@media(max-width:850px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:540px){h1{font-size:28px}main{grid-template-columns:1fr;max-width:400px}.controls{position:static}#count{margin-left:0}}</style>
<header><h1>预算按分类，提醒有分寸。</h1><p>每月或每年，为一级、二级分类分别设置额度。默认只看两条超额信息，更多规则同页展开；记账只提示本次分类的相关预算。</p><div class="links"><a href="../../docs/category-budget-2026-09-10.md">设计与验收</a><a href="../../docs/icloud-sharing-plan-2026-09-10.md">iCloud 共享方案（尚未启用）</a><a href="screenshots.json">截图来源</a></div></header>
<nav class="controls" aria-label="截图筛选"><div class="inner"><select id="device" aria-label="设备"><option value="pro">iPhone 17 Pro</option><option value="compact">iPhone SE 3</option><option value="all">两个设备</option></select><button data-group="summary" aria-pressed="true">统计与记账</button><button data-group="manage" aria-pressed="false">规则管理</button><button data-group="adapt" aria-pressed="false">深色与大字号</button><button data-group="all" aria-pressed="false">全部</button><span id="count" aria-live="polite"></span></div></nav>
<main>${cards}</main><footer>2026-09-10 · iOS 26.5 Simulator 原生截图。使用 2022–2026 年隔离测试样本，个人账本未用于写入测试。本页不代表 iCloud 或真机验收。</footer>
<script>let group='summary';const device=document.querySelector('#device');function render(){let n=0;document.querySelectorAll('figure').forEach(f=>{const show=(device.value==='all'||f.dataset.device===device.value)&&(group==='all'||f.dataset.group===group);f.hidden=!show;if(show)n++});document.querySelector('#count').textContent=n+' 张原生截图'}device.addEventListener('change',render);document.querySelectorAll('button[data-group]').forEach(b=>b.addEventListener('click',()=>{group=b.dataset.group;document.querySelectorAll('button[data-group]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));render()}));render();</script></html>`);
console.log(`Wrote ${screenshots.length} native screenshots.`);
