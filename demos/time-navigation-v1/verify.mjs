import fs from 'node:fs';
import assert from 'node:assert/strict';
import {periodRange,step,recordsIn,totals,validStep,current,comparisonRange} from './model.mjs';

const data=JSON.parse(fs.readFileSync(new URL('../../Fixtures/stats-500.json',import.meta.url),'utf8'));
const checks=[];
function check(name,body){body();checks.push(name);}
check('闰年 2 月包含 29 日',()=>assert.deepEqual(periodRange({kind:'month',year:2024,month:2}),['2024-02-01','2024-02-29']));
check('相邻月份跨年',()=>assert.deepEqual(step({kind:'month',year:2023,month:1},-1),{kind:'month',year:2022,month:12}));
check('本月截至今天',()=>assert.deepEqual(periodRange(current()),['2026-09-01','2026-09-10']));
check('本年截至今天',()=>assert.deepEqual(periodRange({kind:'year',year:2026}),['2026-01-01','2026-09-10']));
check('不翻到未来月份',()=>assert.equal(validStep(current(),1),false));
check('不翻到演示起点以前',()=>assert.equal(validStep({kind:'month',year:2022,month:1},-1),false));
check('本月使用上月同期作为基期',()=>assert.deepEqual(comparisonRange(current()),['2026-08-01','2026-08-10']));
check('2024 年 2 月既有样例有 7 笔',()=>assert.equal(recordsIn(data.transactions,periodRange({kind:'month',year:2024,month:2})).length,7));
const month=recordsIn(data.transactions,periodRange(current()));
check('本月既有样例 4 笔且净支出 501.05',()=>{assert.equal(month.length,4);assert.equal(totals(month).net,50105);});
check('仅退款月份保持负净支出',()=>assert.equal(totals(recordsIn(data.transactions,periodRange({kind:'month',year:2023,month:1}))).net,-1200000));
check('包含跨年范围的首尾两天',()=>{const records=recordsIn(data.transactions,['2022-12-31','2023-01-15']);assert(records.some(t=>t.id.raw==='tx-000'));assert(records.some(t=>t.id.raw==='tx-470'));assert.equal(records.length,2);});
check('删除记录、其他账本不进入全部结果',()=>assert.equal(recordsIn(data.transactions,periodRange({kind:'all'})).length,470));
console.log(JSON.stringify({passed:true,checks,fixtureRecords:data.transactions.length,currentMonth:{count:month.length,netCents:totals(month).net}},null,2));
