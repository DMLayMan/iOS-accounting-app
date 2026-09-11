import fs from 'node:fs';
import path from 'node:path';

const base = path.resolve('evidence/ledger-feed');
const batches = {
  pro: ['pro-confirm-shots', 'pro-flow-final-shots'],
  compact: ['compact-confirm-shots', 'compact-flow-final-shots'],
};
const titles = {
  '01-ledger-cumulative': '账本 · 累计收支', '02-ledger-accounts-summary': '账户余额与累计口径',
  '03-new-ledger-form': '新建账本 · 一个名称即可开始', '04-new-ledger-selected': '创建后直接使用',
  '05-switch-with-create': '切换列表也能直接新建', '10-feed-current-month': '流水 · 当前月份',
  '11-feed-all-years': '一键查看全部年份', '12-feed-leap-month': '跳转到 2024 年 2 月',
  '13-custom-date-range': '指定日期范围 · 包含首尾两天', '14-range-and-category': '日期与分类联动筛选',
  '15-refund-month': '只有退款的月份', '16-empty-month-recovery': '空月份与恢复入口',
  '20-dark-ledger': '深色账本', '21-dark-feed': '深色流水', '22-dark-date-picker': '深色年份与月份选择',
  '30-large-ledger': '最大字号账本', '31-large-new-ledger': '最大字号新建表单',
  '32-large-feed': '最大字号流水', '33-large-date-picker': '最大字号时间选择',
};
const screenshots = [];
for (const [device, sources] of Object.entries(batches)) {
  const selected = new Map();
  for (const source of sources) {
    const folder = path.join(base, source);
    if (!fs.existsSync(path.join(folder, 'manifest.json'))) continue;
    for (const test of JSON.parse(fs.readFileSync(path.join(folder, 'manifest.json'), 'utf8'))) {
      for (const attachment of test.attachments ?? []) {
        const name = attachment.suggestedHumanReadableName?.split('_0_')[0];
        if (!titles[name] || attachment.isAssociatedWithFailure) continue;
        selected.set(name, {source, attachment});
      }
    }
  }
  fs.mkdirSync(path.join(base, 'verified', device), {recursive: true});
  for (const [name, {source, attachment}] of [...selected].sort(([a], [b]) => a.localeCompare(b))) {
    const file = `verified/${device}/${name}.png`;
    fs.copyFileSync(path.join(base, source, attachment.exportedFileName), path.join(base, file));
    screenshots.push({device, name, title: titles[name], group: Number(name.slice(0, 2)) < 10 ? 'ledger' : Number(name.slice(0, 2)) < 20 ? 'feed' : 'adapt', file, source, attachment: attachment.exportedFileName});
  }
}
fs.writeFileSync(path.join(base, 'screenshots.json'), JSON.stringify(screenshots, null, 2));
const cards = screenshots.map(s => `<figure data-device="${s.device}" data-group="${s.group}"><a href="${s.file}" target="_blank"><img src="${s.file}" alt="${s.title}" loading="lazy" width="320"></a><figcaption><strong>${s.title}</strong><span>${s.device === 'pro' ? 'iPhone 17 Pro' : 'iPhone SE 3'} · 原生截图</span></figcaption></figure>`).join('\n');
fs.writeFileSync(path.join(base, 'index.html'), `<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>余记 · 账本与流水</title>
<style>
:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;color:#222b27;background:#f6f7f5;color-scheme:light}*{box-sizing:border-box}body{margin:0}header,main,footer{max-width:1100px;margin:auto;padding:28px 24px}.eyebrow{color:#367961;font-size:13px;font-weight:600}h1{font-size:clamp(27px,4vw,40px);line-height:1.3;margin:14px 0}p{font-size:15px;line-height:1.8;color:#58635b;max-width:760px}a{color:#367961;text-underline-offset:4px}.links{display:flex;gap:24px;font-size:14px;flex-wrap:wrap}.controls{position:sticky;top:0;z-index:1;background:#f6f7f5;border-block:1px solid #dce2dc;padding:12px 24px}.control-inner{max-width:1052px;margin:auto;display:flex;align-items:center;gap:10px;flex-wrap:wrap}button,select{font:inherit;font-size:14px;min-height:44px;border:1px solid #d4ddd5;border-radius:24px;padding:0 16px;background:white;color:#39493f;cursor:pointer}button[aria-pressed=true]{background:#367961;color:white;border-color:#367961}button:focus-visible,select:focus-visible,a:focus-visible{outline:3px solid #87ae96;outline-offset:3px}#count{font-size:13px;color:#6e7972;margin-left:auto}main{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:28px 24px}figure{margin:0;min-width:0}figure[hidden]{display:none}figure a{display:block;border:1px solid #e0e5df;border-radius:22px;overflow:hidden;background:white}img{width:100%;height:auto;display:block}figcaption{padding:12px 2px;line-height:1.6}figcaption strong{display:block;font-size:15px;font-weight:600}figcaption span{font-size:12px;color:#7c857e}footer{border-top:1px solid #dce2dc;font-size:13px;line-height:1.8;color:#6e7972}@media(max-width:850px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:540px){main{grid-template-columns:1fr;max-width:400px}.controls{position:static}#count{margin-left:0}}
</style><header><div class="eyebrow">余记 · iOS 原生验收 · 2026.09.10</div><h1>账本看累计，流水按时间查。</h1><p>账本集中展示累计收支、账户余额和记录概况，切换与新建直接可见。流水保留日期入口，支持历史月份、任意日期范围与分类组合筛选。</p><div class="links"><a href="../../docs/ledger-feed-2026-09-10.md">设计决策与验收记录</a><a href="screenshots.json">截图来源</a></div></header>
<nav class="controls" aria-label="截图筛选"><div class="control-inner"><select id="device" aria-label="设备"><option value="pro">iPhone 17 Pro</option><option value="compact">iPhone SE 3</option><option value="all">两个设备</option></select><button data-group="ledger" aria-pressed="true">账本与新建</button><button data-group="feed" aria-pressed="false">流水与日期</button><button data-group="adapt" aria-pressed="false">深色与大字号</button><button data-group="all" aria-pressed="false">全部</button><span id="count" aria-live="polite"></span></div></nav>
<main>${cards}</main><footer>均为隔离数据下的原生 Simulator 截图。样例覆盖 2022–2026 年，计算口径与测试结果见验收记录。未完成真机触觉和完整 VoiceOver 验收。</footer>
<script>let group='ledger';const device=document.querySelector('#device');function render(){let n=0;document.querySelectorAll('figure').forEach(f=>{const show=(device.value==='all'||f.dataset.device===device.value)&&(group==='all'||f.dataset.group===group);f.hidden=!show;if(show)n++});document.querySelector('#count').textContent=n+' 张原生截图'}device.addEventListener('change',render);document.querySelectorAll('button[data-group]').forEach(b=>b.addEventListener('click',()=>{group=b.dataset.group;document.querySelectorAll('button[data-group]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));render()}));render();</script></html>`);
console.log(`Wrote ${screenshots.length} native screenshots.`);
