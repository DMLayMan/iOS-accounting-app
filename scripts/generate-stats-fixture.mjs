import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const root = path.resolve(import.meta.dirname, '..');
const id = raw => ({raw});
const day = text => { const [year,month,day] = text.split('-').map(Number); return {year,month,day}; };
const key = d => `${d.year}-${String(d.month).padStart(2,'0')}-${String(d.day).padStart(2,'0')}`;
const today = day('2026-09-10');
const stamp = '2026-09-10T00:00:00Z';
let seed = 93741;
const rand = n => { seed = (Math.imul(seed,1664525)+1013904223)>>>0; return seed % n; };
const excluded = d => d.year===2023 && d.month<=3;
const randomDay = () => { let d; do { d = day(new Date(Date.UTC(2022,0,1)+rand(1714)*86400000).toISOString().slice(0,10)); } while(excluded(d)); return d; };
const ledgers = ['stress','other'].map((s,i)=>({id:id(s),name:i?'隔离账本':'五年压力测试 · 500 条样例',currencyCode:'CNY',archived:false,sortOrder:i,createdAt:'2022-01-01T00:00:00Z'}));
const accounts = ledgers.flatMap(l=>['cash','bank'].map((s,i)=>({id:id(`${l.id.raw}-${s}`),ledgerID:l.id,name:i?'银行卡':'现金',openingBalanceCents:i?500000:10000,startDay:day('2022-01-01'),archived:false,sortOrder:i,updatedAt:stamp})));
const groups = [['food','餐饮',['正餐','咖啡茶饮','买菜']],['home','居住',['房租','水电网络']],['travel','出行',['公共交通','打车','旅行']],['shop','购物',['日用品','数码家电']],['fun','娱乐',['影音游戏','电影演出']],['health','健康',['医疗','运动']],['work','工作收入',['工资','奖金']],['extra','其他收入',['礼金','兼职']]];
const categories = ledgers.flatMap(l=>groups.flatMap(([s,name,children],i)=>{const kind=i<6?'expense':'income';const parent=`${l.id.raw}-${s}`;return [{id:id(parent),ledgerID:l.id,kind,name,archived:false,sortOrder:i},...children.map((name,j)=>({id:id(`${parent}-${j}`),ledgerID:l.id,kind,parentID:id(parent),name,archived:s==='fun'&&j===1,sortOrder:j}))];}));
let transactions=[];
function add(kind,date,amount,category,ledger='stress',original) {const n=transactions.length;const t={id:id(`tx-${String(n).padStart(3,'0')}`),ledgerID:id(ledger),operationID:`stress-op-${n}`,revision:1,kind,amountCents:amount,date,accountID:id(`${ledger}-${n%2?'bank':'cash'}`),tagIDs:[],note:n%4===0?'一次普通消费，备注不参与分类筛选':n%19===0?'较长备注：旅行期间与朋友一起吃饭，记录上下文，返回统计后仍应保留原来的时间与分类。':'',createdAt:stamp,updatedAt:stamp};if(category)t.categoryID=id(category);if(original)t.originalExpenseID=original.id;if(kind==='transfer')t.transferToAccountID=id(`${ledger}-${n%2?'cash':'bank'}`);transactions.push(t);return t;}
const big = add('expense',day('2022-12-31'),1200000,'stress-shop-1');
add('expense',day('2022-01-01'),12345,'stress-food-0');
add('expense',day('2024-02-29'),290029,'stress-travel-2');
add('expense',today,9999,'stress-food-1');
// Guarantee a spread across all observed months except the deliberate refund-only / empty quarter.
for(let y=2022;y<=2026;y++) for(let m=1;m<=12;m++) {const d={year:y,month:m,day:5};if(key(d)>key(today)||excluded(d))continue;add('expense',d,1000+rand(70000),`stress-food-${m%3}`);}
while(transactions.length<360){const ledger=transactions.length>=355?'other':'stress';const leaves=categories.filter(c=>c.ledgerID.raw===ledger&&c.kind==='expense'&&c.parentID);add('expense',randomDay(),1+rand(180000),leaves[rand(leaves.length)].id.raw,ledger);}
for(let n=0;n<80;n++){const ledger=n>=77?'other':'stress';add('income',randomDay(),300000+rand(1500000),`${ledger}-${n%4?'work':'extra'}-${n%2}`,ledger);}
for(let n=0;n<30;n++)add('transfer',randomDay(),1000+rand(250000),null,n>=28?'other':'stress');
add('refund',day('2023-01-15'),1200000,null,'stress',big);
for(let n=1;n<30;n++){const orig=transactions[4+n];const start=Date.UTC(orig.date.year,orig.date.month-1,orig.date.day);let d=day(new Date(Math.min(start+(15+n*3)*86400000,Date.UTC(2026,8,10))).toISOString().slice(0,10));if(excluded(d))d=day('2023-04-01');add('refund',d,Math.max(1,Math.floor(orig.amountCents*(n%2?0.5:1))),null,'stress',orig);}
// Trash remains in the snapshot but must not enter statistics or balances.
for(let n=320;n<340;n++)transactions[n].deletedAt=stamp;
const data={schemaVersion:1,ledgers,accounts,categories,tags:[],transactions,drafts:[{ledgerID:id('stress'),kind:'expense',expression:'123456',date:today,accountID:id('stress-cash'),categoryID:id('stress-food-0'),tagIDs:[],note:'未保存草稿，不进入统计',updatedAt:stamp}],activeLedgerID:id('stress'),settings:{hapticsEnabled:true,reduceMotion:false,appearance:'light',icloudEnabled:false},appliedOperations:transactions.map(t=>t.operationID)};
assert.equal(transactions.length,500);assert.equal(new Set(transactions.map(t=>t.id.raw)).size,500);
for(const t of transactions){assert(key(t.date)<=key(today));if(t.kind==='refund'){const orig=transactions.find(x=>x.id.raw===t.originalExpenseID.raw);assert(orig.kind==='expense'&&!orig.deletedAt&&orig.amountCents>=t.amountCents&&key(orig.date)<=key(t.date));}}
const active=transactions.filter(t=>!t.deletedAt&&t.ledgerID.raw==='stress');
const effective=t=>t.kind==='refund'?transactions.find(x=>x.id.raw===t.originalExpenseID.raw).categoryID?.raw:t.categoryID?.raw;
const selected=(from,to,kind,cat)=>active.filter(t=>key(t.date)>=from&&key(t.date)<=to&&(!kind||(kind==='expense'?['expense','refund'].includes(t.kind):t.kind===kind))&&(!cat||effective(t)===cat||categories.find(c=>c.id.raw===effective(t))?.parentID?.raw===cat));
const sum=(ts,k)=>ts.filter(t=>t.kind===k).reduce((s,t)=>s+t.amountCents,0);
const summary=(from,to)=>{const ts=selected(from,to);const expense=sum(ts,'expense'),refund=sum(ts,'refund'),income=sum(ts,'income');return {from,to,expense,refund,netExpense:expense-refund,income,surplus:income-expense+refund};};
const breakdown=(from,to,kind,parentLevel=false)=>{const groups=new Map();for(const t of selected(from,to,kind)){let c=categories.find(c=>c.id.raw===effective(t));if(parentLevel)c=categories.find(p=>p.id.raw===c.parentID.raw);const v=groups.get(c.id.raw)||{id:c.id.raw,expense:0,refund:0,count:0,transactionIDs:[]};v.transactionIDs.push(t.id.raw);if(t.kind==='refund')v.refund+=t.amountCents;else {v.expense+=t.amountCents;v.count++;}groups.set(c.id.raw,v);}return [...groups.values()].map(v=>({...v,transactionIDs:v.transactionIDs.sort()})).sort((a,b)=>a.id.localeCompare(b.id));};
const monthEnd=(y,m)=>key({year:y,month:m,day:new Date(Date.UTC(y,m,0)).getUTCDate()});
const first=(y,m)=>key({year:y,month:m,day:1});
function compare(from,to,baseFrom,baseTo,unequal=false){const current=summary(from,to).netExpense,base=summary(baseFrom,baseTo).netExpense;const status=baseFrom<'2022-01-01'?'baseNotCovered':unequal?'unequalLength':base===0?'baseZero':base<0?'baseNegative':'ok';return {from,to,baseFrom,baseTo,current,base,delta:current-base,percent:status==='ok'?(current-base)*100/base:null,status};}
const months=[];
for(let y=2022;y<=2026;y++)for(let m=1;m<=12;m++){if(first(y,m)>key(today))continue;const to=y===today.year&&m===today.month?key(today):monthEnd(y,m);const from=first(y,m);const pm=m===1?12:m-1,py=m===1?y-1:y;const partial=y===today.year&&m===today.month;months.push({year:y,month:m,summary:summary(from,to),expense:breakdown(from,to,'expense'),income:breakdown(from,to,'income'),parents:breakdown(from,to,'expense',true),mom:compare(from,to,first(py,pm),partial?key({year:py,month:pm,day:today.day}):monthEnd(py,pm)),yoy:compare(from,to,first(y-1,m),partial?key({year:y-1,month:m,day:today.day}):monthEnd(y-1,m))});}
const years=[2022,2023,2024,2025,2026].map(year=>{const from=first(year,1),to=year===2026?key(today):monthEnd(year,12);return {year,summary:summary(from,to),yoy:compare(from,to,first(year-1,1),year===2026?'2025-09-10':monthEnd(year-1,12))};});
const balances=accounts.map(a=>({id:a.id.raw,cents:a.openingBalanceCents+transactions.filter(t=>!t.deletedAt&&t.ledgerID.raw===a.ledgerID.raw).reduce((s,t)=>s+(t.accountID.raw===a.id.raw?(t.kind==='expense'||t.kind==='transfer'?-t.amountCents:t.amountCents):0)+(t.kind==='transfer'&&t.transferToAccountID.raw===a.id.raw?t.amountCents:0),0)}));
const oracle={today,totalRecords:500,activeMain:active.length,trash:20,otherLedger:10,from:'2022-01-01',to:key(today),total:summary('2022-01-01',key(today)),months,years,balances};
fs.mkdirSync(path.join(root,'Fixtures'),{recursive:true});fs.writeFileSync(path.join(root,'Fixtures/stats-500.json'),JSON.stringify(data,null,2)+'\n');fs.writeFileSync(path.join(root,'Fixtures/stats-500-oracle.json'),JSON.stringify(oracle,null,2)+'\n');
console.log(JSON.stringify({records:500,main:active.length,trash:20,other:10,months:months.length,years:years.length,total:oracle.total},null,2));
