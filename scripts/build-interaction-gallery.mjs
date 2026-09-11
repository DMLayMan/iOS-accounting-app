import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..');
const out=path.join(root,'evidence/interaction-sheets');
const labels={
 '20-new-entry-auto-draft':['关闭即保留','新建录入不再弹出三选一。关闭自动保留草稿，保存后才进入统计。'],
 '21-draft-restored':['重启后继续','金额算式、分类与备注恢复，不需要重新填写。'],
 '22-clear-draft-inline':['主动清空草稿','底部确认替换数字键盘，保留继续编辑的选择。'],
 '23-edit-cancel-inline':['取消编辑，留在当前页确认','系统键盘和金额键盘均收起；继续编辑或放弃修改。'],
 '24-other-draft-preserved':['编辑与草稿相互独立','修改已入账记录，不会误删另一笔尚未完成的草稿。'],
 '25-seven-tenths-sheet':['七分屏明细','上方仍能看到统计页，向上展开查看更多流水。'],
 '26-linked-leaf-transactions':['二级分类直接联动','轻点分类，同一面板里的金额、笔数与流水一起更新。'],
 '27-comparison-linked-sheet':['变化与明细放在一起','点变化来源查看分类，切换本期、基期直接更新流水。'],
 '28-base-period-linked-list':['原地核对基期','不再跳转新页面；完成后返回原统计位置。'],
 '29-dark-large-text-exit':['深色与大字号的退出确认','两项选择都可触达，按钮使用适合深色背景的文字对比度。'],
 '17-large-text-dark-drilldown':['大字号与深色','辅助字号默认展开，所有内容可以滚动查看。']
};
const shots=new Map();
for(const [folder,device] of [['native-shots','pro'],['final-pro-shots','pro'],['compact-shots','se'],['layout-pro-shots','pro'],['layout-se-shots','se'],['exit-pro-shots','pro'],['exit-se-shots','se']]){
 const m=path.join(out,folder,'manifest.json');if(!fs.existsSync(m))continue;
 for(const test of JSON.parse(fs.readFileSync(m)))for(const a of test.attachments){
  const name=a.suggestedHumanReadableName.split('_0_')[0];if(!labels[name]||!a.exportedFileName.endsWith('.png'))continue;
  const rel=`shots/${device}/${name}.png`;fs.mkdirSync(path.dirname(path.join(out,rel)),{recursive:true});fs.copyFileSync(path.join(out,folder,a.exportedFileName),path.join(out,rel));shots.set(`${device}-${name}`,{name,device,rel});
 }
}
const ordered=[...shots.values()].sort((a,b)=>Object.keys(labels).indexOf(a.name)-Object.keys(labels).indexOf(b.name)||a.device.localeCompare(b.device));
const cards=ordered.map(s=>`<article data-device="${s.device}"><button class="shot" data-src="${s.rel}" aria-label="放大${labels[s.name][0]}"><img src="${s.rel}" loading="lazy" alt="${labels[s.name][0]}的原生模拟器截图"></button><div class="caption"><small>${s.device==='pro'?'iPhone 17 Pro':'iPhone SE'}</small><h2>${labels[s.name][0]}</h2><p>${labels[s.name][1]}</p></div></article>`).join('');
fs.writeFileSync(path.join(out,'index.html'),`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>余记 · 更轻的退出与下钻</title><style>
*{box-sizing:border-box}body{margin:0;background:#f5f5f0;color:#25352d;font:16px/1.7 -apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif}main{max-width:1150px;margin:auto;padding:48px 24px 80px}h1{font-size:clamp(32px,5vw,48px);line-height:1.25;margin:12px 0 20px;letter-spacing:-1px}p{color:#647267;margin:8px 0}header p{max-width:720px;font-size:18px}.tag{font-size:12px;color:#39775c;letter-spacing:2px}.note{background:#e8eee5;padding:20px;border-radius:16px;margin:26px 0}a{color:#2f7558;text-underline-offset:4px}.toolbar{display:flex;gap:10px;margin:28px 0 18px;flex-wrap:wrap}button{font:inherit;cursor:pointer;border:1px solid #d1dbd0;border-radius:30px;background:white;color:#3d5f48;padding:9px 16px}button[aria-pressed=true]{background:#34765c;color:white}button:focus-visible,a:focus-visible{outline:3px solid #b77633;outline-offset:3px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:20px}article{background:white;border:1px solid #e1e6dc;border-radius:18px;overflow:hidden}.shot{display:block;width:100%;border:0;border-radius:0;background:#e9ede5;padding:15px 8px 0}.shot img{display:block;height:420px;max-width:100%;object-fit:contain;margin:auto;border-radius:20px}.caption{padding:18px}small{color:#83947f}h2{font-size:18px;line-height:1.5;margin:7px 0}article p{font-size:14px}.footer{font-size:13px;margin-top:28px}dialog{border:0;border-radius:18px;max-width:96vw;max-height:95vh;padding:14px;background:#eef0ea}dialog::backdrop{background:#000b}dialog img{display:block;max-width:87vw;max-height:80vh;margin:10px auto}dialog button{display:block;margin-left:auto}[hidden]{display:none!important}@media(max-width:850px){.grid{grid-template-columns:repeat(2,1fr)}}@media(max-width:520px){main{padding:28px 16px}.grid{grid-template-columns:1fr}.shot img{height:460px}}
</style><main><header><span class="tag">YUJI / IOS / 2026.09.10</span><h1>少一次弹窗，<br>少几次跳转。</h1><p>新建录入关闭时保留草稿。统计在七分屏里筛选、核对与下钻，原来的浏览位置留在身后。</p></header><div class="note">本页展示原生模拟器截图。基于五年 500 条隔离样例，覆盖草稿恢复、编辑取消、分类联动、同环比与小屏显示。<br><a href="../../docs/interaction-sheets-2026-09-10.md">交互规则与验证记录</a> · <a href="verification.json">本次验收结果</a></div><div class="toolbar"><button data-device="pro" aria-pressed="true">iPhone 17 Pro</button><button data-device="se" aria-pressed="false">iPhone SE</button><button data-device="all" aria-pressed="false">全部截图</button></div><div class="grid">${cards}</div><p class="footer">已验证范围以验收记录为准。真机与旧版 iOS 运行仍待验证。个人数据与测试样例分开存储。</p></main><dialog><button id="close">关闭 ×</button><img alt="放大截图"></dialog><script>
const filter=d=>{document.querySelectorAll('article').forEach(x=>x.hidden=d!=='all'&&x.dataset.device!==d);document.querySelectorAll('.toolbar button').forEach(x=>x.setAttribute('aria-pressed',String(x.dataset.device===d)))};document.querySelectorAll('.toolbar button').forEach(b=>b.onclick=()=>filter(b.dataset.device));filter('pro');const dialog=document.querySelector('dialog');document.querySelectorAll('.shot').forEach(b=>b.onclick=()=>{dialog.querySelector('img').src=b.dataset.src;dialog.querySelector('img').alt=b.getAttribute('aria-label');dialog.showModal()});document.querySelector('#close').onclick=()=>dialog.close();dialog.onclick=e=>{if(e.target===dialog)dialog.close()};</script></html>`);
console.log(JSON.stringify({output:out,images:shots.size}));
