import {TODAY,FIRST,pad,iso,current,periodRange,recordsIn,totals,comparisonRange} from '../time-navigation-v1/model.mjs';

const $=selector=>document.querySelector(selector);
const icon=name=>`<svg aria-hidden="true"><use href="#${name}"/></svg>`;
const escape=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=cents=>new Intl.NumberFormat('zh-CN',{style:'currency',currency:'CNY'}).format(cents/100);
const formatDate=date=>date.replaceAll('-','.');
let data, selection=current(), page='stats', panel=false, mode='month', choosingYear=2026, category=null, visibleCount=10;
let rangeDraft={start:'2026-09-01',end:TODAY};
const colors=['#427d64','#a18669','#739c9b','#97718d','#849867','#8a90ae'];
const categoryMap=new Map(),transactionMap=new Map(),accountMap=new Map();
const selectedTitle=()=>selection.kind==='month'?`${selection.year} 年 ${selection.month} 月`:selection.kind==='year'?`${selection.year} 年`:selection.kind==='all'?'全部时间':'自定日期范围';
function categoryFor(transaction) {
  const id=transaction.kind==='refund'?transactionMap.get(transaction.originalExpenseID?.raw)?.categoryID?.raw:transaction.categoryID?.raw;
  return categoryMap.get(id);
}
function parentFor(transaction) { const c=categoryFor(transaction); return c?.parentID?categoryMap.get(c.parentID.raw):c; }
function selectedRecords(){return recordsIn(data.transactions,periodRange(selection));}
function matches(transaction){return !category||(parentFor(transaction)?.id.raw??'uncategorized')===category;}
function announce(message){$('#announcement').textContent=message;}
function focusPeriod(){($('#timebar [aria-pressed="true"]')??$('#chooseDate')).focus({preventScroll:true});}
function apply(value){selection=value;panel=false;visibleCount=10;render();$('#workspace').scrollTop=0;focusPeriod();announce(`已切换到${selectedTitle()}，统计与流水共用此时间。`);}
function periodStrip(){
  if(!['month','year'].includes(selection.kind))return `<span class="range-title">${selectedTitle()}</span>`;
  const items=[];
  const firstYear=Number(FIRST.slice(0,4)),lastYear=Number(TODAY.slice(0,4)),lastMonth=Number(TODAY.slice(5,7));
  for(let year=firstYear;year<=lastYear;year++){
    if(selection.kind==='year'){
      items.push(`<button class="period-item annual" data-rail-year="${year}" aria-label="查看 ${year} 年" aria-pressed="${selection.year===year}" tabindex="${selection.year===year?0:-1}">${year}</button>`);
    }else{
      for(let month=1;month<=(year===lastYear?lastMonth:12);month++){
        const active=selection.year===year&&selection.month===month;
        items.push(`<button class="period-item" data-rail-month="${year}-${pad(month)}" aria-label="查看 ${year} 年 ${month} 月" aria-pressed="${active}" tabindex="${active?0:-1}"><span>${month} 月</span>${year!==selection.year?`<small>${year}</small>`:''}</button>`);
      }
    }
  }
  return `<span class="period-year">${selection.kind==='year'?'年份':`${selection.year} 年`}</span><div class="strip-window"><div class="period-strip" aria-label="${selection.kind==='year'?'年份':'月份'}，横向滚动后点击选择">${items.join('')}</div></div>`;
}
function centerSelectedPeriod(){
  const strip=$('.period-strip'),active=strip?.querySelector('[aria-pressed="true"]');
  if(!strip||!active)return;
  strip.scrollLeft=Math.max(0,active.offsetLeft-(strip.clientWidth-active.offsetWidth)/2);
}
function renderTime(){
  const unit=selection.kind==='year'?'年':'月';
  $('#timebar').innerHTML=`${periodStrip()}<button class="calendar-trigger" id="chooseDate" aria-label="选择时间，当前${selectedTitle()}" aria-expanded="${panel}" aria-controls="periodPanel">${icon('calendar')}</button>`;
  centerSelectedPeriod();
  const range=periodRange(selection), isCurrent=selection.kind==='month'&&selection.year===2026&&selection.month===9||selection.kind==='year'&&selection.year===2026;
  $('#context').innerHTML=`<span>${formatDate(range[0])}–${formatDate(range[1])}${range[1]===TODAY?' · 截至今天':''}</span>${isCurrent?'':`<button id="returnCurrent">回本${unit}</button>`}`;
  $('#periodPanel').hidden=!panel;
  if(panel) renderPanel();
  requestAnimationFrame(centerSelectedPeriod);
}
function renderPanel(){
  let body='';
  if(mode==='month'){
    body=`<div class="years" aria-label="选择年份">${Array.from({length:5},(_,i)=>2022+i).map(year=>`<button data-year="${year}" aria-label="${year} 年" aria-pressed="${year===choosingYear}">${year}</button>`).join('')}</div><div class="months" aria-label="选择月份">${Array.from({length:12},(_,i)=>i+1).map(month=>{
      const chosen=selection.kind==='month'&&selection.year===choosingYear&&selection.month===month;
      return `<button data-month="${month}" aria-label="${choosingYear} 年 ${month} 月" aria-pressed="${chosen}" ${choosingYear===2026&&month>9?'disabled':''}>${month} 月${choosingYear===2026&&month===9?'<small>本月</small>':''}</button>`;
    }).join('')}</div>`;
  }else if(mode==='year'){
    body=`<div class="year-grid" aria-label="选择整年">${Array.from({length:5},(_,i)=>2022+i).map(year=>`<button data-annual="${year}" aria-pressed="${selection.kind==='year'&&selection.year===year}">${year} 年</button>`).join('')}</div>`;
  }else{
    body=`<div class="range-fields"><label>开始日期<input id="startDate" type="date" value="${escape(rangeDraft.start)}" min="${FIRST}" max="${TODAY}" aria-describedby="rangeError"></label><label>结束日期<input id="endDate" type="date" value="${escape(rangeDraft.end)}" min="${FIRST}" max="${TODAY}" aria-describedby="rangeError"></label></div><p class="error" id="rangeError" aria-live="polite"></p><button class="apply-range" id="applyRange">应用日期范围</button>`;
  }
  $('#periodPanel').innerHTML=`<div class="panel-head"><div class="modes" aria-label="时间选择方式">${[['month','按月'],['year','按年'],['custom','自定']].map(([value,label])=>`<button data-mode="${value}" aria-pressed="${mode===value}">${label}</button>`).join('')}</div><button class="close" id="closePanel" aria-label="取消选择时间">${icon('close')}</button></div>${body}<div class="panel-footer"><button id="quickCurrent">回到本月</button><button id="allTime">全部时间</button></div>`;
  if(mode==='custom')validateRange();
}
function validateRange(){
  const {start,end}=rangeDraft;
  const valid=Boolean(start&&end&&start<=end&&start>=FIRST&&end<=TODAY&&$('#startDate').validity.valid&&$('#endDate').validity.valid);
  $('#rangeError').textContent=!start||!end?'请选择开始和结束日期':start>end?'结束日期不能早于开始日期':start<FIRST||end>TODAY?'请选择 2022.01.01 至今天的日期':'';
  $('#applyRange').disabled=!valid;
  return valid;
}
function comparisonHTML(){
  const baseRange=comparisonRange(selection);
  if(!baseRange)return '<p class="comparison">当前展示所选范围的实际收支。<br>同环比与周期预算仅在按月、按年查看时展示。</p>';
  const range=periodRange(selection),base=totals(recordsIn(data.transactions,baseRange)).net,now=totals(selectedRecords()).net;
  const reason=baseRange[0]<FIRST?'基期早于记账起点':base===0?'基期为零，暂不计算增长率':base<0?'基期净支出为负，暂不计算增长率':`净支出${now>=base?'增加':'减少'} ${money(Math.abs(now-base))}（${Math.abs((now-base)/base*100).toFixed(1)}%）`;
  return `<p class="comparison"><strong>${selection.kind==='year'?'年度同比':'环比'} · ${reason}</strong><br>本期 ${formatDate(range[0])}–${formatDate(range[1])}<br>基期 ${formatDate(baseRange[0])}–${formatDate(baseRange[1])}</p>`;
}
function distributionHTML(records){
  const sums=new Map();
  for(const t of records){if(t.kind!=='expense')continue;const c=parentFor(t);const id=c?.id.raw??'uncategorized';const v=sums.get(id)??{id,name:c?.name??'未分类',amount:0};v.amount+=t.amountCents;sums.set(id,v);}
  const rows=[...sums.values()].sort((a,b)=>b.amount-a.amount),total=rows.reduce((sum,r)=>sum+r.amount,0);
  if(!total)return '<p class="comparison">这段时间没有支出，退款与收入仍在下方明细展示。</p>';
  let offset=0;
  const circles=rows.map((r,i)=>{const percent=r.amount/total*100;const html=`<circle cx="60" cy="60" r="44" pathLength="100" fill="none" stroke="${colors[i%colors.length]}" stroke-width="15" stroke-dasharray="${percent} ${100-percent}" stroke-dashoffset="${-offset}" transform="rotate(-90 60 60)"/>`;offset+=percent;return html;}).join('');
  return `<div class="section-heading"><h3>支出去向</h3><span>点击分类筛选明细</span></div><div class="distribution"><svg class="donut" viewBox="0 0 120 120" role="img" aria-label="本期支出分类占比，右侧提供数值">${circles}<text x="60" y="58" text-anchor="middle">支出</text><text x="60" y="76" text-anchor="middle">${rows.length} 类</text></svg><div class="rank">${rows.slice(0,4).map((r,i)=>`<button data-category="${escape(r.id)}" aria-pressed="${category===r.id}"><span class="key"><i class="dot" style="background:${colors[i%colors.length]}"></i>${escape(r.name)}</span><span class="value">${(r.amount/total*100).toFixed(1)}%</span></button>`).join('')}</div></div>`;
}
function listHTML(records){
  const filtered=records.filter(matches).sort((a,b)=>iso(b.date).localeCompare(iso(a.date))||a.id.raw.localeCompare(b.id.raw));
  const amount=totals(filtered);
  let html=`<div class="section-heading"><h3>${page==='stats'?'本期明细':'收支记录'}</h3><span>${filtered.length} 笔</span></div>`;
  if(category)html+=`<div class="filter"><span>${escape(categoryMap.get(category)?.name??'未分类')} · 净支出 ${money(amount.net)}</span><button id="clearCategory" aria-label="清除分类筛选">${icon('close')}</button></div>`;
  if(!filtered.length)return html+'<div class="empty">这段时间没有符合条件的记录。<br>时间与分类条件仍保留。<button id="emptyReset">清除条件，查看本月</button></div>';
  const groups=new Map();
  for(const t of filtered.slice(0,visibleCount)){const day=iso(t.date);if(!groups.has(day))groups.set(day,[]);groups.get(day).push(t);}
  for(const [day,items] of groups){
    html+=`<section class="date-group"><h4>${formatDate(day)}</h4>`;
    for(const t of items){
      const name=categoryFor(t)?.name??(t.kind==='transfer'?'账户转账':'未分类');
      html+=`<div class="transaction ${escape(t.kind)}"><p>${t.kind==='refund'?'退款 · ':''}${escape(name)}<small>${escape(accountMap.get(t.accountID.raw)?.name??'账户')}</small></p><span class="money">${t.kind==='expense'?'−':t.kind==='transfer'?'':'+'}${money(t.amountCents)}</span></div>`;
    }
    html+='</section>';
  }
  if(filtered.length>visibleCount)html+=`<button class="load-more" id="loadMore">继续查看 ${filtered.length-visibleCount} 笔</button>`;
  if(page==='stats')html+='<button class="load-more" data-page="feed">在流水继续查看</button>';
  return html;
}
function render(){
  if(!data)return;
  $('#pageTitle').textContent=page==='stats'?'统计':'流水';
  document.querySelectorAll('.tabs [data-page]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.page===page));
  renderTime();
  const records=selectedRecords(),sum=totals(records);
  const summary=page==='stats'
    ? `<section class="summary"><p class="caption">净支出</p><p class="total money">${money(sum.net)}</p><p class="composition">支出 ${money(sum.expense)} − 退款 ${money(sum.refund)}</p><div class="totals"><p>收入<strong class="money">${money(sum.income)}</strong></p><p>结余<strong class="money">${money(sum.surplus)}</strong></p></div></section>${comparisonHTML()}${distributionHTML(records)}`
    : `<section class="feed-summary"><p>本期净支出 <strong class="money">${money(sum.net)}</strong></p><span>收入 ${money(sum.income)} · 退款 ${money(sum.refund)}</span></section>`;
  $('#content').innerHTML=summary+listHTML(records);
}
document.addEventListener('input',event=>{
  if(event.target.id==='startDate'||event.target.id==='endDate'){rangeDraft[event.target.id==='startDate'?'start':'end']=event.target.value;validateRange();}
});
document.addEventListener('click',event=>{
  const button=event.target.closest('button');if(!button||button.disabled)return;
  if(button.dataset.page){page=button.dataset.page;panel=false;visibleCount=10;render();$('#workspace').scrollTop=0;return;}
  if(button.dataset.railMonth){const [year,month]=button.dataset.railMonth.split('-').map(Number);apply({kind:'month',year,month});return;}
  if(button.dataset.railYear){apply({kind:'year',year:Number(button.dataset.railYear)});return;}
  if(button.dataset.mode){mode=button.dataset.mode;renderPanel();return;}
  if(button.dataset.year){choosingYear=Number(button.dataset.year);renderPanel();return;}
  if(button.dataset.month){apply({kind:'month',year:choosingYear,month:Number(button.dataset.month)});return;}
  if(button.dataset.annual){apply({kind:'year',year:Number(button.dataset.annual)});return;}
  if(button.dataset.category){category=category===button.dataset.category?null:button.dataset.category;render();return;}
  switch(button.id){
    case 'chooseDate':panel=!panel;mode=['month','year'].includes(selection.kind)?selection.kind:'custom';choosingYear=selection.year??Number(periodRange(selection)[0].slice(0,4));rangeDraft={start:periodRange(selection)[0],end:periodRange(selection)[1]};renderTime();break;
    case 'closePanel':panel=false;renderTime();$('#chooseDate').focus();break;
    case 'returnCurrent':apply(selection.kind==='year'?{kind:'year',year:2026}:current());break;
    case 'quickCurrent':apply(current());break;
    case 'allTime':apply({kind:'all'});break;
    case 'applyRange':if(validateRange())apply({kind:'custom',...rangeDraft});break;
    case 'clearCategory':category=null;render();break;
    case 'emptyReset':category=null;apply(current());break;
    case 'loadMore':visibleCount+=20;render();break;
    case 'reset':category=null;page='stats';apply(current());break;
    case 'compact':case 'dark':case 'large':$('.device').classList.toggle(button.id);button.setAttribute('aria-pressed',$('.device').classList.contains(button.id));centerSelectedPeriod();break;
    case 'retry':load();break;
  }
});
document.addEventListener('keydown',event=>{
  if(event.key==='Escape'&&panel){panel=false;renderTime();$('#chooseDate').focus();return;}
  const item=event.target.closest('.period-item');
  if(!item||!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;
  const items=[...item.parentElement.querySelectorAll('button')],index=items.indexOf(item);
  const next=event.key==='Home'?items[0]:event.key==='End'?items.at(-1):items[index+(event.key==='ArrowLeft'?-1:1)];
  if(next){event.preventDefault();item.tabIndex=-1;next.tabIndex=0;next.focus({preventScroll:true});next.scrollIntoView({block:'nearest',inline:'nearest'});}
});
window.addEventListener('resize',centerSelectedPeriod);
async function load(){
  try{const response=await fetch('../../Fixtures/stats-500.json');if(!response.ok)throw new Error('fixture unavailable');data=await response.json();for(const c of data.categories)categoryMap.set(c.id.raw,c);for(const t of data.transactions)transactionMap.set(t.id.raw,t);for(const a of data.accounts)accountMap.set(a.id.raw,a);render();}
  catch{$('#content').innerHTML='<p class="empty">演示数据暂时无法读取。<button id="retry">重新读取</button></p>';}
}
load();
