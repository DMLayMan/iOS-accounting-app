import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

const base = path.resolve('evidence/time-wheel');
const batches = ['pro', 'compact'].map(device => {
  const result = JSON.parse(fs.readFileSync(path.join(base, `${device}-summary.json`), 'utf8'));
  assert.equal(result.failedTests, 0);
  assert.equal(result.result, 'Passed');
  return { device, result };
});
const unitLog = fs.readFileSync(path.join(base, 'swift-test.log'), 'utf8');
assert.match(unitLog, /Executed 101 tests, with 0 failures/);
const titles = {
  '40-swipe-hint': ['main', '首次提示 · 露出相邻月份'],
  '41-swipe-previous-month': ['main', '月份居中 · 松手选中'],
  '42-cross-year-december': ['main', '滑过一月 · 年份自动变为上一年'],
  '42-leap-month-after-swipes': ['main', '连续翻月 · 跨年到闰月'],
  '43-feed-shared-swipe-month': ['main', '流水 · 继续查看同一期'],
  '44-tap-picker-still-available': ['main', '点击日期 · 仍可直接选'],
  '50-chart-scroll-keeps-date': ['flow', '滚动图表 · 保持当前日期'],
  '51-empty-month-not-skipped': ['flow', '空月份 · 自然翻页不跳过'],
  '60-year-swipe': ['flow', '年度 · 一次切换一年'],
  '69-reduced-motion-setting': ['adapt', '减弱动态 · 通过实际开关启用'],
  '70-dark-reduced-motion': ['adapt', '深色 · 减弱动态效果'],
  '71-large-reduced-motion': ['adapt', '大字号 · 完整年份与月份'],
  '72-large-feed-swipe': ['adapt', '大字号流水 · 日期和笔数可见']
};
const screenshots = [];
for (const device of ['pro', 'compact']) {
  const source = `${device}-final-shots`;
  const manifest = JSON.parse(fs.readFileSync(path.join(base, source, 'manifest.json'), 'utf8'));
  fs.mkdirSync(path.join(base, 'verified', device), { recursive: true });
  for (const test of manifest) for (const attachment of test.attachments ?? []) {
    const name = attachment.suggestedHumanReadableName.split('_0_')[0];
    if (!titles[name] || !attachment.exportedFileName.endsWith('.png')) continue;
    const file = `verified/${device}/${name}.png`;
    fs.copyFileSync(path.join(base, source, attachment.exportedFileName), path.join(base, file));
    screenshots.push({ device, name, group: titles[name][0], title: titles[name][1], file,
      source: `${source}/${attachment.exportedFileName}`, test: test.testIdentifier });
  }
  assert.equal(screenshots.filter(s => s.device === device).length, Object.keys(titles).length);
}
screenshots.sort((a, b) => a.name.localeCompare(b.name) || a.device.localeCompare(b.device));
fs.writeFileSync(path.join(base, 'screenshots.json'), JSON.stringify(screenshots, null, 2));
const verification = {
  checkedAt: new Date().toISOString(),
  unitTests: { passed: 101, failed: 0, log: 'swift-test.log' },
  uiTests: { passed: batches.reduce((sum, b) => sum + b.result.passedTests, 0), failed: 0, batches },
  screenshots: screenshots.length,
  visualReview: { passes: 2, fixes: ['AX sizes use separate full-width month row', 'Dark selected month uses the existing light sage token'] },
  video: { file: 'wheel.mp4', source: 'final-motion-raw.mp4', timing: 'video-timing.json', speed: 'original' },
  superseded: 'time-swipe evidence is from the earlier hidden row gesture, not this delivered component',
  limitations: ['iOS 26.5 Simulator only', 'Physical haptics, frame pacing and VoiceOver speech not accepted', 'Unrelated UI test suites not rerun']
};
fs.writeFileSync(path.join(base, 'verification.json'), JSON.stringify(verification, null, 2));
const cards = screenshots.map(s => `<figure data-device="${s.device}" data-group="${s.group}"><a href="${s.file}" target="_blank" rel="noopener"><img src="${s.file}" alt="${s.title}" loading="lazy"></a><figcaption><strong>${s.title}</strong><span>${s.device === 'pro' ? 'iPhone 17 Pro' : 'iPhone SE 3'} · iOS 26.5 Simulator</span></figcaption></figure>`).join('\n');
fs.writeFileSync(path.join(base, 'index.html'), `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>余记 · 滑动切换时间</title>
<style>:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;color:#222b27;background:#f6f7f5;color-scheme:light}*{box-sizing:border-box}body{margin:0}header,main,footer,.demo{max-width:1100px;margin:auto;padding:24px}h1{font-size:30px;line-height:1.3;margin:4px 0 14px}p{font-size:15px;line-height:1.8;color:#58635b;max-width:760px}a{color:#367961;text-underline-offset:4px}.links{display:flex;gap:24px;flex-wrap:wrap;font-size:14px}.demo{display:flex;align-items:center;gap:40px;padding-top:0}.demo video{display:block;max-height:490px;max-width:45%;border:1px solid #dce2dc;border-radius:22px;background:#fff}.demo h2{font-size:22px}.demo ul{padding-left:20px;color:#58635b;line-height:2;font-size:15px}.controls{position:sticky;top:0;z-index:1;background:#f6f7f5;border-block:1px solid #dce2dc;padding:10px 24px}.inner{max-width:1052px;margin:auto;display:flex;align-items:center;gap:10px;flex-wrap:wrap}button,select{font:inherit;font-size:14px;min-height:44px;border:1px solid #d4ddd5;border-radius:24px;padding:0 16px;background:white;color:#39493f;cursor:pointer}button[aria-pressed=true],#play{background:#367961;color:white;border-color:#367961}button:focus-visible,select:focus-visible,a:focus-visible{outline:3px solid #87ae96;outline-offset:3px}#count{font-size:13px;color:#58635b;margin-left:auto}main{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:28px 24px}figure{margin:0;min-width:0}figure[hidden]{display:none}figure a{display:block;border:1px solid #e0e5df;border-radius:20px;overflow:hidden;background:white}img{width:100%;height:auto;display:block}figcaption{padding:12px 2px;line-height:1.6}figcaption strong{display:block;font-size:15px;font-weight:600}figcaption span{font-size:12px;color:#58635b}footer{border-top:1px solid #dce2dc;font-size:13px;line-height:1.8;color:#58635b}@media(max-width:850px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:540px){h1{font-size:26px}.demo{flex-direction:column;gap:12px;align-items:flex-start}.demo video{max-width:100%;max-height:500px;margin:auto}main{grid-template-columns:1fr;max-width:400px}.controls{position:static}#count{margin-left:0}}</style>
<header><h1>看得见的月份，可以左右滑。</h1><p>顶部年份旁直接露出相邻月份。横滑居中选择，跨年时年份同步更新；点击年份仍可直接定位。流水和统计共享选择。</p><div class="links"><a href="../../docs/time-wheel-2026-09-10.md">设计与验收记录</a><a href="verification.json">实际测试结果</a><a href="screenshots.json">截图来源</a></div></header>
<section class="demo" aria-label="原生滑动录像"><video id="motion" controls playsinline preload="metadata" poster="verified/pro/40-swipe-hint.png" src="wheel.mp4"></video><div><h2>原生操作录像</h2><p>横滑月份，居中吸附选中；也可以直接点相邻月份。录像保持原速，页面来自真实模拟器。</p><ul><li>相邻月份可见，当前月份绿色短线标记</li><li>首次显示“左右滑动选月”</li><li>跨过 12 月／1 月，年份同步变化</li><li>点年份打开完整选择器</li></ul><button id="play">播放滑动演示</button></div></section>
<nav class="controls" aria-label="原生截图筛选"><div class="inner"><select id="device" aria-label="设备"><option value="pro">iPhone 17 Pro</option><option value="compact">iPhone SE 3</option><option value="all">两个设备</option></select><button data-group="main" aria-pressed="true">日期与流水</button><button data-group="flow" aria-pressed="false">操作边界</button><button data-group="adapt" aria-pressed="false">深色与大字号</button><span id="count" aria-live="polite"></span></div></nav>
<main>${cards}</main><footer>本页展示原生截图和录像，使用 2022–2026 年的隔离样例。各图来自不同操作步骤。真机触觉、帧率与 VoiceOver 实际朗读尚未验收。</footer>
<script>let group='main';const device=document.querySelector('#device');function render(){let count=0;document.querySelectorAll('figure').forEach(f=>{const show=(device.value==='all'||f.dataset.device===device.value)&&f.dataset.group===group;f.hidden=!show;if(show)count++});document.querySelector('#count').textContent=count+' 张原生截图'}device.addEventListener('change',render);document.querySelectorAll('button[data-group]').forEach(b=>b.addEventListener('click',()=>{group=b.dataset.group;document.querySelectorAll('button[data-group]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));render()}));document.querySelector('#play').addEventListener('click',async()=>{const v=document.querySelector('#motion');v.currentTime=0;try{await v.play()}catch{document.querySelector('#play').textContent='请点击视频播放控件'}});render();</script></html>`);
console.log(`Wrote ${screenshots.length} verified native screenshots.`);
