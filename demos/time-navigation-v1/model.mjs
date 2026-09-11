export const TODAY = '2026-09-10';
export const FIRST = '2022-01-01';
export const pad = value => String(value).padStart(2, '0');
export const iso = day => `${day.year}-${pad(day.month)}-${pad(day.day)}`;
export const monthEnd = (year, month) => new Date(Date.UTC(year, month, 0)).getUTCDate();
export const current = () => ({ kind:'month', year:2026, month:9 });
export function periodRange(selection) {
  if (selection.kind === 'all') return [FIRST, TODAY];
  if (selection.kind === 'custom') return [selection.start, selection.end < TODAY ? selection.end : TODAY];
  const start = `${selection.year}-${selection.kind === 'year' ? '01' : pad(selection.month)}-01`;
  const end = selection.kind === 'year' ? `${selection.year}-12-31` : `${selection.year}-${pad(selection.month)}-${monthEnd(selection.year, selection.month)}`;
  return [start, end < TODAY ? end : TODAY];
}
export function step(selection, direction) {
  if (selection.kind === 'year') return {...selection, year:selection.year + direction};
  const date = new Date(Date.UTC(selection.year, selection.month - 1 + direction, 1));
  return {kind:'month',year:date.getUTCFullYear(),month:date.getUTCMonth()+1};
}
export function validStep(selection, direction) {
  if (!['month','year'].includes(selection.kind)) return false;
  const candidate = step(selection,direction);
  const [start,end] = periodRange(candidate);
  return start <= TODAY && end >= FIRST;
}
export function recordsIn(transactions, range) {
  return transactions.filter(t => t.ledgerID.raw === 'stress' && !t.deletedAt && iso(t.date) >= range[0] && iso(t.date) <= range[1]);
}
export function totals(records) {
  const result={expense:0,income:0,refund:0};
  for(const record of records) if(record.kind in result) result[record.kind]+=record.amountCents;
  return {...result,net:result.expense-result.refund,surplus:result.income-result.expense+result.refund};
}
export function comparisonRange(selection) {
  if(!['month','year'].includes(selection.kind)) return null;
  if(selection.kind==='year') {
    const lastYear=selection.year-1;
    return [`${lastYear}-01-01`,selection.year===2026 ? `${lastYear}-09-10` : `${lastYear}-12-31`];
  }
  const previous=step(selection,-1);
  const day = selection.year===2026 && selection.month===9 ? Math.min(10,monthEnd(previous.year,previous.month)) : monthEnd(previous.year,previous.month);
  return [`${previous.year}-${pad(previous.month)}-01`,`${previous.year}-${pad(previous.month)}-${pad(day)}`];
}
