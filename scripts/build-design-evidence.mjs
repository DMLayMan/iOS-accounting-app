import fs from 'node:fs';
import path from 'node:path';

const base = path.resolve('evidence/design-quality');
const batches = {
  pro: ['pro-confirm-shots', 'pro-layout-final-shots', 'pro-stability-shots'],
  compact: ['compact-confirm-shots', 'compact-layout-final-shots', 'compact-stability-shots'],
};
const titles = {
  '01-current-month': '当前月份与收支口径',
  '02-refund-only-month': '只有退款的月份',
  '03-refund-drilldown': '退款分类与同页明细',
  '04-original-refund-detail': '原支出与退款关系',
  '05-empty-month-negative-base': '空月份与负基期',
  '06-before-recording-start': '早于记账起点的比较',
  '07-leap-month-transactions': '闰月明细与金额排序',
  '08-ranking-by-count': '按笔数排列分类',
  '09-year-negative-bar': '年度负值与月份跳转',
  '10-comparison-exact-windows': '同比日期范围',
  '11-comparison-base-transactions': '同页查看基期',
  '12-income-distribution': '收入分类',
  '13-pie-selection-inline': '饼图选中状态',
  '14-edited-total-updated': '编辑后刷新明细',
  '15-large-refund-prefill': '退款额度与金额',
  '16-large-text-dark-summary': '深色大字号统计',
  '17-large-text-dark-drilldown': '大字号同页明细',
  '18-five-year-feed': '保留流水筛选',
  '19-empty-filter-recovery': '搜索无结果',
  '20-new-entry-auto-draft': '新建记账',
  '21-draft-restored': '重启恢复草稿',
  '22-clear-draft-inline': '清空草稿确认',
  '23-edit-cancel-inline': '编辑取消：页内决策',
  '24-other-draft-preserved': '其他草稿不受影响',
  '25-inline-parent-selected': '选一级：饼图与明细联动',
  '26-inline-leaf-transactions': '选二级：2 条流水 · ¥139.90',
  '27-inline-comparison': '同比在当前页面展开',
  '28-inline-base-period': '基期图表与明细同步',
  '29-dark-large-text-exit': '深色大字号退出决策',
  '30-category-create-sheet': '新增二级分类 · 七分屏',
  '31-category-icon-name': '同一表单内填名与选图标',
  '32-category-created-selected': '创建后立即选中',
  '33-category-edit-restored': '重启后图标与名称保持',
  '40-home': '账本首页', '41-transfer': '转账', '42-ledger-switch': '切换账本',
  '43-me': '我的', '44-accounts': '账户列表', '45-account-editor': '账户编辑',
  '46-account-invalid-stays': '无效金额就地纠错', '47-category-library': '全部分类与管理',
  '48-ledgers': '账本管理', '49-trash': '最近删除', '50-data': '备份、恢复与导出',
  '51-settings': '外观与反馈', '52-feed': '流水', '53-search-filter': '分类搜索与筛选',
  '54-transaction-detail': '单笔详情', '55-account-picker': '选择账户', '56-date-picker': '选择日期',
  '57-category-search': '快速查找分类', '58-category-search-empty': '分类搜索无结果',
  '59-category-cancel-inline': '分类修改：继续或放弃',
  '60-dark-entry': '深色记账', '61-dark-category': '深色分类编辑',
  '62-backup-review': '恢复前先看替换范围', '63-backup-recovery-available': '替换后可找回恢复点',
  '70-large-home': '最大字号首页', '71-large-entry': '最大字号记账',
  '72-large-category': '大字号分类纵向布局', '73-large-me': '最大字号管理入口',
  '01-entertainment-single-row': '娱乐分类保持一行', '02-note-without-amount-keypad': '备注与金额键盘互斥',
  '03-native-long-press-reordered': '长按拖动排序', '04-order-after-relaunch': '重启保留排序',
  '05-search-locates-next-page': '搜索定位下一页分类', '06-native-cross-page-drag': '跨页拖动分类',
};
const focus = new Set(['30-category-create-sheet', '31-category-icon-name', '32-category-created-selected', '25-inline-parent-selected', '26-inline-leaf-transactions', '59-category-cancel-inline']);
const inlineCategory = new Set(['01-entertainment-single-row', '02-note-without-amount-keypad', '03-native-long-press-reordered', '04-order-after-relaunch', '05-search-locates-next-page', '06-native-cross-page-drag']);
const cards = [];
const provenance = [];
for (const [device, sources] of Object.entries(batches)) {
  const selected = new Map();
  for (const source of sources) {
    const folder = path.join(base, source);
    if (!fs.existsSync(path.join(folder, 'manifest.json'))) continue;
    for (const test of JSON.parse(fs.readFileSync(path.join(folder, 'manifest.json'), 'utf8'))) {
      for (const attachment of test.attachments ?? []) {
        const name = attachment.suggestedHumanReadableName?.split('_0_')[0];
        if (!/^\d{2}-/.test(name ?? '') || name.startsWith('99-') || attachment.isAssociatedWithFailure) continue;
        selected.set(name, {source, attachment});
      }
    }
  }
  fs.mkdirSync(path.join(base, 'verified', device), {recursive: true});
  for (const [name, {source, attachment}] of [...selected].sort(([a], [b]) => a.localeCompare(b))) {
    const relative = `verified/${device}/${name}.png`;
    fs.copyFileSync(path.join(base, source, attachment.exportedFileName), path.join(base, relative));
    const n = Number(name.slice(0, 2));
    const category = name.includes('category') || inlineCategory.has(name);
    const stats = (n < 20 || n >= 25 && n <= 28) && !inlineCategory.has(name);
    const pages = n >= 40 && n < 60 || n >= 20 && n <= 24 || n === 62 || n === 63;
    const adapt = n >= 60 && n !== 62 && n !== 63 || name.includes('large-text') || name.includes('dark-large');
    const groups = [focus.has(name) ? 'focus' : '', category ? 'category' : '', stats ? 'stats' : '', pages ? 'pages' : '', adapt ? 'adapt' : ''].filter(Boolean);
    const title = titles[name] ?? name.replace(/^\d+-/, '').replaceAll('-', ' ');
    cards.push(`<figure data-device="${device}" data-groups="${groups.join(' ')}"><a href="${relative}" target="_blank" aria-label="放大：${title}"><img src="${relative}" alt="${title}，${device === 'pro' ? 'iPhone 17 Pro' : 'iPhone SE 3'} 原生截图" loading="lazy" width="320"></a><figcaption><strong>${title}</strong><span>${device === 'pro' ? 'iPhone 17 Pro' : 'iPhone SE 3'} · 原生截图</span></figcaption></figure>`);
    provenance.push({device, name, source, file: relative, attachment: attachment.exportedFileName, test: 'See source manifest and corresponding xcresult'});
  }
}
fs.writeFileSync(path.join(base, 'screenshots.json'), JSON.stringify(provenance, null, 2));
fs.writeFileSync(path.join(base, 'index.html'), `<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>余记 · 全页面设计验收</title>
<style>
:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;color:#222b27;background:#f6f7f5;color-scheme:light}*{box-sizing:border-box}body{margin:0}header,main,footer{max-width:1120px;margin:auto;padding:32px 24px}header{padding-bottom:20px}.eyebrow{color:#367961;font-size:13px;font-weight:600;letter-spacing:.08em}h1{font-size:clamp(27px,4vw,42px);line-height:1.25;letter-spacing:-.025em;margin:14px 0}p{font-size:15px;line-height:1.8;color:#58635b;max-width:780px}a{color:#367961;text-underline-offset:4px}.links{display:flex;gap:24px;font-size:14px;flex-wrap:wrap}.controls{position:sticky;top:0;z-index:1;background:#f6f7f5;border-block:1px solid #dce2dc;padding:12px 24px}.control-inner{max-width:1072px;margin:auto;display:flex;align-items:center;gap:10px;flex-wrap:wrap}button,select{font:inherit;font-size:14px;min-height:44px;border:1px solid #d4ddd5;border-radius:24px;padding:0 16px;background:white;color:#39493f;cursor:pointer}button[aria-pressed=true]{background:#367961;color:white;border-color:#367961}button:focus-visible,select:focus-visible,a:focus-visible{outline:3px solid #87ae96;outline-offset:3px}#count{font-size:13px;color:#6e7972;margin-left:auto}main{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:32px 24px;padding-top:28px}figure{margin:0;min-width:0}figure[hidden]{display:none}figure a{display:block;border:1px solid #e0e5df;border-radius:22px;overflow:hidden;background:#fff}img{width:100%;height:auto;display:block}figcaption{padding:14px 2px;line-height:1.55}figcaption strong{display:block;font-size:15px;font-weight:600}figcaption span{font-size:12px;color:#7c857e}footer{border-top:1px solid #dce2dc;padding-top:16px;font-size:13px;line-height:1.8;color:#6e7972}@media(max-width:850px){main{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:540px){main{grid-template-columns:1fr;max-width:400px}.controls{position:static}header{padding-top:24px}#count{margin-left:0}button,select{padding:0 12px}}
</style><header><div class="eyebrow">余记 · iOS 原生验收 · 2026.09.10</div><h1>分类更顺手，统计在同页完成。</h1><p>新增分类用七分屏完成名称与图标；饼图、分类和流水直接联动。这里展示真实 Simulator 截图，点击可放大，切换设备查看小屏表现。</p><div class="links"><a href="../../docs/design-quality-2026-09-10.md">设计决策与验收记录</a><a href="../../docs/design-skills-installed.md">开源技能安装记录</a><a href="screenshots.json">截图来源清单</a></div></header>
<nav class="controls" aria-label="截图筛选"><div class="control-inner"><select id="device" aria-label="设备"><option value="pro">iPhone 17 Pro</option><option value="compact">iPhone SE 3</option><option value="all">两个设备</option></select><button data-group="focus" aria-pressed="true">重点改动</button><button data-group="category" aria-pressed="false">分类</button><button data-group="stats" aria-pressed="false">统计与明细</button><button data-group="pages" aria-pressed="false">其余页面</button><button data-group="adapt" aria-pressed="false">深色与大字号</button><button data-group="all" aria-pressed="false">全部</button><span id="count" aria-live="polite"></span></div></nav>
<main>${cards.join('\n')}</main><footer>截图来自隔离测试账本，部分用例会修改自己的数据来检验刷新与恢复。统计布局取最终布局批次；其余页面取全量通过批次。测试不能替代长期使用评价，真机触觉、完整 VoiceOver 和系统文件保存目标尚未验收。</footer>
<script>let group='focus';const device=document.querySelector('#device');function render(){let n=0;document.querySelectorAll('figure').forEach(f=>{const show=(device.value==='all'||f.dataset.device===device.value)&&(group==='all'||f.dataset.groups.split(' ').includes(group));f.hidden=!show;if(show)n++});document.querySelector('#count').textContent=n+' 张原生截图'}device.addEventListener('change',render);document.querySelectorAll('button[data-group]').forEach(b=>b.addEventListener('click',()=>{group=b.dataset.group;document.querySelectorAll('button[data-group]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));render()}));render();</script></html>`);
console.log(`Wrote ${cards.length} native screenshots and evidence gallery.`);
