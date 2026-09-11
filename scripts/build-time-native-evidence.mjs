import fs from 'node:fs';
import path from 'node:path';

const base = path.resolve('evidence/time-native');
const titles = {
  '01-stats-month-center-tab': ['main', '统计 · 紧凑年月与中间记账'],
  '04-feed-same-leap-month': ['main', '流水 · 与统计共享期间'],
  '20-tab-账本': ['main', '账本 · 系统 Tab 中间入口'],
  '02-month-picker': ['time', '月份 · 直接选择'],
  '03-year-jump': ['time', '跨年 · 不必逐月翻找'],
  '10-year-picker': ['time', '年度 · 直接选年'],
  '11-year-statistics': ['time', '年度 · 汇总与逐月分析'],
  '12-custom-range': ['time', '自定 · 首尾日期均包含'],
  '05-empty-month': ['time', '空月份 · 保留范围与恢复入口'],
  '06-all-time-statistics': ['time', '全部 · 五年汇总'],
  '13-future-range': ['time', '未来 · 明确实际统计边界'],
  '14-comparison-linked': ['time', '同环比 · 基期同页联动'],
  '21-entry-keyboard-exclusive': ['entry', '备注 · 文字键盘与金额键盘互斥'],
  '22-entry-amount-keypad': ['entry', '录入 · 金额与分类'],
  '23-save-back-to-feed': ['entry', '保存 · 回到原 Tab'],
  '30-dark-statistics': ['adapt', '深色 · 日期与中间记账'],
  '31-dark-picker': ['adapt', '深色 · 时间面板'],
  '32-large-statistics': ['adapt', '大字号 · 统计'],
  '33-large-picker': ['adapt', '大字号 · 可滚动时间面板'],
  '34-large-feed': ['adapt', '大字号 · 精简固定头部'],
  '35-large-entry': ['adapt', '大字号 · 录入与退出']
};
const screenshots = [];
for (const device of ['pro', 'compact']) {
  const source = `${device}-final-shots`;
  const manifest = JSON.parse(fs.readFileSync(path.join(base, source, 'manifest.json'), 'utf8'));
  fs.mkdirSync(path.join(base, 'verified', device), {recursive: true});
  for (const test of manifest) for (const attachment of test.attachments ?? []) {
    const name = attachment.suggestedHumanReadableName.split('_0_')[0];
    if (!titles[name] || !attachment.exportedFileName.endsWith('.png')) continue;
    const file = `verified/${device}/${name}.png`;
    fs.copyFileSync(path.join(base, source, attachment.exportedFileName), path.join(base, file));
    screenshots.push({device, name, group: titles[name][0], title: titles[name][1], file,
      source: `${source}/${attachment.exportedFileName}`, test: test.testIdentifier});
  }
}
screenshots.sort((a, b) => a.name.localeCompare(b.name) || a.device.localeCompare(b.device));
fs.writeFileSync(path.join(base, 'screenshots.json'), JSON.stringify(screenshots, null, 2));
const cards = screenshots.map(s => `<figure data-device="${s.device}" data-group="${s.group}"><a href="${s.file}" target="_blank" rel="noopener"><img src="${s.file}" alt="${s.title}" loading="lazy"></a><figcaption><strong>${s.title}</strong><span>${s.device === 'pro' ? 'iPhone 17 Pro' : 'iPhone SE 3'} · iOS 26.5 Simulator</span></figcaption></figure>`).join('\n');
fs.writeFileSync(path.join(base, 'index.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>余记 · 时间选择与中间记账</title>
<style>:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;color:#222b27;background:#f6f7f5;color-scheme:light}*{box-sizing:border-box}body{margin:0}header,main,footer{max-width:1100px;margin:auto;padding:24px}h1{font-size:30px;line-height:1.3;margin:4px 0 14px}p{font-size:15px;line-height:1.8;color:#58635b;max-width:820px}a{color:#367961;text-underline-offset:4px}.links{display:flex;gap:24px;flex-wrap:wrap;font-size:14px}.controls{position:sticky;top:0;z-index:1;background:#f6f7f5;border-block:1px solid #dce2dc;padding:10px 24px}.inner{max-width:1052px;margin:auto;display:flex;align-items:center;gap:10px;flex-wrap:wrap}button,select{font:inherit;font-size:14px;min-height:44px;border:1px solid #d4ddd5;border-radius:24px;padding:0 16px;background:white;color:#39493f;cursor:pointer}button[aria-pressed=true]{background:#367961;color:white;border-color:#367961}button:focus-visible,select:focus-visible,a:focus-visible{outline:3px solid #87ae96;outline-offset:3px}#count{font-size:13px;color:#58635b;margin-left:auto}main{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:28px 24px}figure{margin:0;min-width:0}figure[hidden]{display:none}figure a{display:block;border:1px solid #e0e5df;border-radius:20px;overflow:hidden;background:white}img{width:100%;height:auto;display:block}figcaption{padding:12px 2px;line-height:1.6}figcaption strong{display:block;font-size:15px;font-weight:600}figcaption span{font-size:12px;color:#58635b}footer{border-top:1px solid #dce2dc;font-size:13px;line-height:1.8;color:#58635b}@media(max-width:850px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:540px){h1{font-size:26px}main{grid-template-columns:1fr;max-width:400px}.controls{position:static}#count{margin-left:0}}</style>
<header><h1>日期收起来，记账放中间。</h1><p>统计与流水共用一个年月入口，点开直接选月、选年或日期范围。底部正中绿色加号打开录入，保存、取消后留在原来的页面。</p><div class="links"><a href="../../docs/time-native-2026-09-10.md">设计与验收记录</a><a href="../time-competitors/index.html">竞品研究</a><a href="screenshots.json">截图来源</a></div></header>
<nav class="controls" aria-label="原生截图筛选"><div class="inner"><select id="device" aria-label="设备"><option value="pro">iPhone 17 Pro</option><option value="compact">iPhone SE 3</option><option value="all">两个设备</option></select><button data-group="main" aria-pressed="true">主页面</button><button data-group="time" aria-pressed="false">选择时间</button><button data-group="entry" aria-pressed="false">记账动线</button><button data-group="adapt" aria-pressed="false">深色与大字号</button><span id="count" aria-live="polite"></span></div></nav>
<main>${cards}</main><footer>原生模拟器截图，点击可放大。使用 2022–2026 年隔离账本测试，个人数据未用于写入测试。真机签名仍未配置；触觉与 VoiceOver 实际朗读未验收。</footer>
<script>let group='main';const device=document.querySelector('#device');function render(){let count=0;document.querySelectorAll('figure').forEach(f=>{const show=(device.value==='all'||f.dataset.device===device.value)&&f.dataset.group===group;f.hidden=!show;if(show)count++});document.querySelector('#count').textContent=count+' 张原生截图'}device.addEventListener('change',render);document.querySelectorAll('button[data-group]').forEach(b=>b.addEventListener('click',()=>{group=b.dataset.group;document.querySelectorAll('button[data-group]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));render()}));render();</script></html>`);
console.log(`Wrote ${screenshots.length} native screenshots.`);
