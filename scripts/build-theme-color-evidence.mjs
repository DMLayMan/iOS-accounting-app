import fs from 'node:fs';
import path from 'node:path';

const base = path.resolve('evidence/theme-color');
const titles = {
  "01-theme-settings": [
    "main",
    "主题 · 六种预设与自定义"
  ],
  "02-plum-statistics": [
    "main",
    "统计 · 主色与收支分工"
  ],
  "03-plum-feed": [
    "main",
    "流水 · 收入与支出"
  ],
  "04-plum-ledger": [
    "flow",
    "账本 · 累计收支"
  ],
  "05-expense-entry": [
    "flow",
    "记账 · 支出暖橙"
  ],
  "06-income-entry": [
    "flow",
    "记账 · 收入青绿"
  ],
  "10-custom-color-editor": [
    "custom",
    "系统颜色选择器"
  ],
  "11-custom-applied": [
    "custom",
    "自定义颜色已应用"
  ],
  "20-dark-settings": [
    "adapt",
    "深色 · 琥珀主题"
  ],
  "21-dark-statistics": [
    "adapt",
    "深色 · 统计"
  ],
  "22-dark-feed": [
    "adapt",
    "深色 · 流水"
  ],
  "23-dark-entry": [
    "adapt",
    "深色 · 记账"
  ],
  "24-large-settings": [
    "adapt",
    "大字号 · 主题设置"
  ],
  "25-large-feed": [
    "adapt",
    "大字号 · 流水"
  ]
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
for (const device of ['pro', 'compact']) {
  for (const name of Object.keys(titles)) {
    if (screenshots.filter(s => s.device === device && s.name === name).length !== 1) {
      throw new Error(`Missing or duplicate native screenshot: ${device}/${name}`);
    }
  }
}
screenshots.sort((a, b) => a.name.localeCompare(b.name) || a.device.localeCompare(b.device));
fs.writeFileSync(path.join(base, 'screenshots.json'), JSON.stringify(screenshots, null, 2));
const cards = screenshots.map(s => `<figure data-device="${s.device}" data-group="${s.group}"><a href="${s.file}" target="_blank" rel="noopener"><img src="${s.file}" alt="${s.title}" loading="lazy"></a><figcaption><strong>${s.title}</strong><span>${s.device === 'pro' ? 'iPhone 17 Pro' : 'iPhone SE 3'} · iOS 26.5 Simulator</span></figcaption></figure>`).join('\n');
fs.writeFileSync(path.join(base, 'index.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>余记 · 主题与收支配色</title>
<style>:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;color:#222b27;background:#f6f7f5;color-scheme:light}*{box-sizing:border-box}body{margin:0}header,main,footer{max-width:1100px;margin:auto;padding:24px}h1{font-size:30px;line-height:1.3;margin:4px 0 14px}p{font-size:15px;line-height:1.8;color:#58635b;max-width:820px}a{color:#367961;text-underline-offset:4px}.links{display:flex;gap:24px;flex-wrap:wrap;font-size:14px}.controls{position:sticky;top:0;z-index:1;background:#f6f7f5;border-block:1px solid #dce2dc;padding:10px 24px}.inner{max-width:1052px;margin:auto;display:flex;align-items:center;gap:10px;flex-wrap:wrap}button,select{font:inherit;font-size:14px;min-height:44px;border:1px solid #d4ddd5;border-radius:24px;padding:0 16px;background:white;color:#39493f;cursor:pointer}button[aria-pressed=true]{background:#367961;color:white;border-color:#367961}button:focus-visible,select:focus-visible,a:focus-visible{outline:3px solid #87ae96;outline-offset:3px}#count{font-size:13px;color:#58635b;margin-left:auto}main{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:28px 24px}figure{margin:0;min-width:0}figure[hidden]{display:none}figure a{display:block;border:1px solid #e0e5df;border-radius:20px;overflow:hidden;background:white}img{width:100%;height:auto;display:block}figcaption{padding:12px 2px;line-height:1.6}figcaption strong{display:block;font-size:15px;font-weight:600}figcaption span{font-size:12px;color:#58635b}footer{border-top:1px solid #dce2dc;font-size:13px;line-height:1.8;color:#58635b}@media(max-width:850px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:540px){h1{font-size:26px}main{grid-template-columns:1fr;max-width:400px}.controls{position:static}#count{margin-left:0}}</style>
<header><h1>让颜色各司其职。</h1><p>支出暖橙、收入青绿、退款蓝色、转账中性。六种主题和自选颜色影响操作与选中状态，收支含义保持一致。</p><div class="links"><a href="../../docs/theme-color-2026-09-10.md">设计与验收记录</a><a href="verification.json">验收结果</a><a href="screenshots.json">截图来源</a></div></header>
<nav class="controls" aria-label="原生截图筛选"><div class="inner"><select id="device" aria-label="设备"><option value="pro">iPhone 17 Pro</option><option value="compact">iPhone SE 3</option><option value="all">两个设备</option></select><button data-group="main" aria-pressed="true">主页面</button><button data-group="flow" aria-pressed="false">账本与记账</button><button data-group="custom" aria-pressed="false">自定义颜色</button><button data-group="adapt" aria-pressed="false">深色与大字号</button><span id="count" aria-live="polite"></span></div></nav>
<main>${cards}</main><footer>原生模拟器截图，点击可放大；各图来自不同操作步骤。点击选色器关闭按钮后保存；按背景调整明暗。草稿与金额、分类数据保持独立。使用 2022–2026 年隔离样例，真机触觉与 VoiceOver 实际朗读尚未验收。</footer>
<script>let group='main';const device=document.querySelector('#device');function render(){let count=0;document.querySelectorAll('figure').forEach(f=>{const show=(device.value==='all'||f.dataset.device===device.value)&&f.dataset.group===group;f.hidden=!show;if(show)count++});document.querySelector('#count').textContent=count+' 张原生截图'}device.addEventListener('change',render);document.querySelectorAll('button[data-group]').forEach(b=>b.addEventListener('click',()=>{group=b.dataset.group;document.querySelectorAll('button[data-group]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));render()}));render();</script></html>`);
console.log(`Wrote ${screenshots.length} native screenshots.`);
