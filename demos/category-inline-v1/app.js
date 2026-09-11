'use strict';
// This prototype uses only in-memory sample data; it never reads or writes a real ledger.
const $ = id => document.getElementById(id);
const icon = name => `<svg aria-hidden="true"><use href="#i-${name}"/></svg>`;
const escapeHTML = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const initial = [
  ['food','餐饮','expense',[['coffee','咖啡茶饮','coffee',12],['lunch','午餐晚餐','meal',20],['breakfast','早餐','bread',9],['snack','零食','cake',4],['fruit','水果','fruit',3],['delivery','外卖','bag',5],['drink','饮品','drink',2],['grocery','买菜','bag',4],['dessert','甜品','cake',1],['hotpot','火锅','bowl',2],['party','聚餐','meal',2],['late','夜宵','bowl',0]]],
  ['transport','出行','expense',[['metro','公共交通','train',18],['taxi','打车','car',7],['fuel','加油','car',2],['parking','停车','car',3],['rail','高铁','train',1],['ride','单车','grid',0],['flight','机票','grid',1],['toll','高速过路','car',0],['service','车辆保养','car',0],['othertrip','其他出行','grid',0]]],
  ['shopping','购物','expense',[['daily','日用百货','bag',8],['clothing','服饰','bag',5],['digital','数码','screen',2],['beauty','个护美妆','heart',1],['books','图书','note',1],['pet','宠物用品','heart',0],['sport','运动装备','grid',0],['hobby','兴趣用品','grid',0],['giftbuy','礼品','gift',0]]],
  ['home','居家','expense',[['rent','房租','home',1],['water','水电燃气','home',2],['internet','网络通信','screen',1],['furniture','家居用品','home',0]]],
  ['fun','娱乐','expense',[['movie','电影演出','screen',3],['game','游戏','grid',1],['fitness','运动健身','heart',2],['travel','旅行休闲','bag',1]]],
  ['health','健康','expense',[['medical','门诊药品','heart',1],['checkup','体检','heart',0]]],
  ['social','人情','expense',[['giftmoney','礼金','gift',2],['donate','公益捐赠','heart',0]]],
  ['other','其他','expense',[['otherexpense','其他支出','grid',0]]],
  ['work','工作','income',[['salary','工资','money',4],['bonus','奖金','gift',1],['sidejob','兼职','money',0]]],
  ['wealth','其他收入','income',[['return','理财收益','money',2],['giftincome','红包礼金','gift',1],['otherincome','其他收入','grid',0]]]
].map(([id,name,kind,children]) => ({id,name,kind,children:children.map(([id,name,icon,used])=>({id,name,icon,used,archived:false})),archived:false}));
let groups=structuredClone(initial),kind='expense',activeGroup='food',selected='coffee',editing=false,expression='36',replaceAmount=true,undoAction=null,toastTimer=null,restoreFocus=null;
const group = () => groups.find(g=>g.id===activeGroup);
const selectedInfo = () => {for(const g of groups){const child=g.children.find(c=>c.id===selected&&!c.archived);if(child&&!g.archived)return {g,child};}return null;};
function announce(text,undo=null){clearTimeout(toastTimer);$('toastText').textContent=text;$('toast').hidden=false;undoAction=undo;$('undo').hidden=!undo;toastTimer=setTimeout(()=>{$('toast').hidden=true;undoAction=null;},6000);}
$('undo').onclick=()=>{if(undoAction)undoAction();undoAction=null;$('toast').hidden=true;render();};
function render(){
  document.querySelectorAll('[data-kind]').forEach(b=>{b.classList.toggle('active',b.dataset.kind===kind);b.setAttribute('aria-pressed',String(b.dataset.kind===kind));});
  $('categoryHeading').textContent=editing?'编辑分类':'分类';$('editToggle').innerHTML=editing?icon('check')+'<span>完成</span>':icon('edit')+'<span>编辑</span>';
  $('parents').classList.toggle('editing',editing);
  $('parents').innerHTML=groups.filter(g=>g.kind===kind&&!g.archived).map(g=>`<button data-group="${g.id}" class="${g.id===activeGroup?'active':''}" aria-pressed="${g.id===activeGroup}" aria-label="${editing?'编辑一级分类 ':''}${escapeHTML(g.name)}">${escapeHTML(g.name)}</button>`).join('')+(editing?'<button id="addGroup" aria-label="新增一级分类">＋ 新增</button>':'');
  $('parents').querySelectorAll('[data-group]').forEach(b=>b.onclick=()=>{activeGroup=b.dataset.group;renderChildren(true);renderParentsSelection();if(editing)openEditor('group',group());});
  if($('addGroup'))$('addGroup').onclick=()=>openEditor('newGroup');
  renderChildren();renderAmount();
}
function renderParentsSelection(){document.querySelectorAll('[data-group]').forEach(b=>{b.classList.toggle('active',b.dataset.group===activeGroup);b.setAttribute('aria-pressed',String(b.dataset.group===activeGroup));});}
const CATEGORY_COLUMNS = 4;
const CATEGORY_PAGE_SIZE = CATEGORY_COLUMNS * 2;
function renderChildren(reset=false){
  const scroll=$('children').scrollLeft;
  const items=group()?.children.filter(c=>!c.archived)||[];
  const pages=[];
  for(let i=0;i<items.length;i+=CATEGORY_PAGE_SIZE){
    pages.push(`<div class="category-page">${items.slice(i,i+CATEGORY_PAGE_SIZE).map(c=>`<button class="child ${c.id===selected?'selected':''} ${editing?'editing':''}" data-child="${c.id}" aria-label="${editing?'编辑二级分类 ':''}${escapeHTML(c.name)}" aria-pressed="${c.id===selected}">${icon(c.icon)}<span>${escapeHTML(c.name)}</span>${editing?'<i class="edit-badge">'+icon('edit')+'</i>':''}</button>`).join('')}</div>`);
  }
  $('children').classList.toggle('single-row',items.length<=CATEGORY_COLUMNS);
  $('children').classList.toggle('editing',editing);
  $('children').innerHTML=pages.join('')||'<div class="category-empty">还没有分类，点右侧新增</div>';
  $('children').querySelectorAll('[data-child]').forEach(b=>b.onclick=()=>{const child=group().children.find(c=>c.id===b.dataset.child);if(editing)openEditor('child',child);else{selected=child.id;renderChildren();}});
  $('children').scrollLeft=reset?0:scroll;
  const info=selectedInfo();$('selectionPath').textContent=editing?'拖动调整顺序 · 轻点编辑名称':info?`已选 ${info.g.name} · ${info.child.name}`:'请选择一个二级分类';
  requestAnimationFrame(updateOverflow);
}
$('addChild').onclick=()=>openEditor('newChild');
function updateOverflow(){const el=$('children'),max=el.scrollWidth-el.clientWidth;const end=max<=2||el.scrollLeft>=max-3;$('nextChildren').hidden=end;$('scrollThumb').parentElement.style.visibility=max>2?'visible':'hidden';$('scrollThumb').style.left=(max>0?Math.min(1,el.scrollLeft/max)*18:0)+'px';}
$('children').addEventListener('scroll',updateOverflow,{passive:true});new ResizeObserver(updateOverflow).observe($('children'));
$('nextChildren').onclick=()=>$('children').scrollBy({left:$('children').clientWidth,behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'});

// Row-major pages keep display, stored order, search order and drag positions aligned.
function moveCategory(id,target,isParent){
  const list=isParent?groups:group().children;
  const from=list.findIndex(c=>c.id===id),to=list.findIndex(c=>c.id===target);
  if(from<0||to<0||from===to)return false;
  list.splice(to,0,list.splice(from,1)[0]);
  return true;
}
let dragSession=null;
function categoryGestures(el,isParent){
  const selector=isParent?'[data-group]':'[data-child]';
  const idOf=node=>isParent?node.dataset.group:node.dataset.child;
  const itemFor=id=>[...el.querySelectorAll(selector)].find(n=>idOf(n)===id);
  let pending=null,holdTimer=null,blockedUntil=0;
  function clearPending(){clearTimeout(holdTimer);pending=null;}
  function redraw(){const scroll=el.scrollLeft;render();el.scrollLeft=scroll;if(dragSession)itemFor(dragSession.id)?.classList.add('drag-source');}
  function startDrag(point,keyboard=false){
    if(dragSession||!pending)return;
    clearTimeout(holdTimer);
    const node=itemFor(pending.id),rect=node.getBoundingClientRect();
    dragSession={id:pending.id,before:structuredClone(groups),originalOrder:(isParent?groups:group().children).map(c=>c.id).join(','),isParent,point,keyboard,frame:null,pageAt:performance.now(),ghost:null};
    if(!keyboard){
      const ghost=node.cloneNode(true);ghost.removeAttribute('id');ghost.removeAttribute(isParent?'data-group':'data-child');ghost.setAttribute('aria-hidden','true');ghost.className+=' drag-ghost';
      Object.assign(ghost.style,{width:rect.width+'px',height:rect.height+'px'});document.body.append(ghost);dragSession.ghost=ghost;
    }
    editing=true;blurNote();document.querySelector('.device').classList.add('sorting');redraw();
    $('reorderStatus').textContent='已拿起分类，移动后松手放置；按 Escape 取消';
    if(keyboard)itemFor(dragSession.id)?.focus();else{positionGhost();dragSession.frame=requestAnimationFrame(tick);}
  }
  function positionGhost(){const d=dragSession;if(d?.ghost){d.ghost.style.left=d.point.x+'px';d.ghost.style.top=d.point.y+'px';}}
  function moveOver(point){
    const d=dragSession;if(!d||d.isParent!==isParent)return;
    d.point=point;positionGhost();
    const bounds=el.getBoundingClientRect();
    if(point.x<bounds.left||point.x>bounds.right||point.y<bounds.top-18||point.y>bounds.bottom+18)return;
    const candidates=[...el.querySelectorAll(selector)].map(node=>({node,rect:node.getBoundingClientRect()})).filter(({rect})=>rect.right>bounds.left+4&&rect.left<bounds.right-4);
    const nearest=candidates.sort((a,b)=>Math.hypot(point.x-(a.rect.left+a.rect.width/2),point.y-(a.rect.top+a.rect.height/2))-Math.hypot(point.x-(b.rect.left+b.rect.width/2),point.y-(b.rect.top+b.rect.height/2)))[0];
    if(nearest&&moveCategory(d.id,idOf(nearest.node),isParent))redraw();
  }
  function tick(time){
    const d=dragSession;if(!d||d.keyboard||d.isParent!==isParent)return;
    const r=el.getBoundingClientRect(),p=d.point;
    if(p.y>=r.top-24&&p.y<=r.bottom+24){
      const direction=p.x<r.left+22?-1:p.x>r.right-22?1:0;
      if(direction){
        const before=el.scrollLeft;
        if(isParent)el.scrollLeft+=direction*4;
        else if(time-d.pageAt>700){el.scrollLeft+=direction*el.clientWidth;d.pageAt=time;}
        if(el.scrollLeft!==before)moveOver(p);
      }
    }
    d.frame=requestAnimationFrame(tick);
  }
  function finish(cancel=false){
    clearPending();const d=dragSession;if(!d||d.isParent!==isParent)return;
    cancelAnimationFrame(d.frame);d.ghost?.remove();dragSession=null;blockedUntil=Date.now()+350;
    document.querySelector('.device').classList.remove('sorting');
    const changed=d.originalOrder!==(isParent?groups:group().children).map(c=>c.id).join(',');
    if(cancel)groups=d.before;
    redraw();
    if(d.keyboard)itemFor(d.id)?.focus();
    $('reorderStatus').textContent=cancel?'已取消排序':'分类已放置';
    if(changed&&!cancel)announce('分类顺序已更新',()=>{groups=d.before;});
  }
  function begin(target,point,pointerType){
    const node=target.closest(selector);if(!node||dragSession)return;
    pending={id:idOf(node),point,scroll:el.scrollLeft,pointerType};
    holdTimer=setTimeout(()=>startDrag(point),420);
  }
  function movement(point,event){
    if(dragSession?.isParent===isParent&&!dragSession.keyboard){event.preventDefault();moveOver(point);return;}
    if(!pending)return;
    const distance=Math.hypot(point.x-pending.point.x,point.y-pending.point.y);
    if(distance<=8)return;
    clearTimeout(holdTimer);
    if(editing){startDrag(point);event.preventDefault();moveOver(point);}
    else if(pending.pointerType==='mouse'){event.preventDefault();el.scrollLeft=pending.scroll-(point.x-pending.point.x);blockedUntil=Date.now()+350;}
    else clearPending(); // Before the long press, a swipe remains native scrolling.
  }
  el.addEventListener('pointerdown',e=>{if(e.pointerType==='mouse'&&e.button===0)begin(e.target,{x:e.clientX,y:e.clientY},'mouse');});
  document.addEventListener('pointermove',e=>{if(e.pointerType==='mouse')movement({x:e.clientX,y:e.clientY},e);});
  document.addEventListener('pointerup',e=>{if(e.pointerType==='mouse')finish();});
  el.addEventListener('touchstart',e=>{if(e.touches.length!==1)return finish(true);const t=e.touches[0];begin(e.target,{x:t.clientX,y:t.clientY},'touch');},{passive:true});
  document.addEventListener('touchmove',e=>{if(e.touches.length!==1)return finish(true);const t=e.touches[0];movement({x:t.clientX,y:t.clientY},e);},{passive:false});
  document.addEventListener('touchend',()=>finish());
  document.addEventListener('touchcancel',()=>finish(true));
  window.addEventListener('blur',()=>finish(true));
  el.addEventListener('contextmenu',e=>e.preventDefault());
  el.addEventListener('click',e=>{if(Date.now()<blockedUntil){e.preventDefault();e.stopPropagation();}},true);
  el.addEventListener('keydown',e=>{
    const node=e.target.closest(selector);if(!node)return;
    if(e.code==='Space'&&!dragSession){e.preventDefault();pending={id:idOf(node)};startDrag(null,true);return;}
    const d=dragSession;if(!d||d.isParent!==isParent||!d.keyboard)return;
    if(e.key==='Enter'||e.code==='Space'){e.preventDefault();finish();return;}
    const step={ArrowLeft:-1,ArrowRight:1,ArrowUp:isParent?-1:-CATEGORY_COLUMNS,ArrowDown:isParent?1:CATEGORY_COLUMNS}[e.key];
    if(step){e.preventDefault();const nodes=[...el.querySelectorAll(selector)],index=nodes.findIndex(n=>idOf(n)===d.id),target=nodes[Math.max(0,Math.min(nodes.length-1,index+step))];moveCategory(d.id,idOf(target),isParent);redraw();itemFor(d.id)?.focus();itemFor(d.id)?.scrollIntoView({block:'nearest',inline:'nearest'});}
  });
  document.addEventListener('keydown',e=>{if(e.key==='Escape'&&dragSession?.isParent===isParent){e.preventDefault();finish(true);}});
}
categoryGestures($('parents'),true);categoryGestures($('children'),false);
$('editToggle').onclick=()=>{blurNote();editing=!editing;render();};
document.querySelectorAll('[data-kind]').forEach(b=>b.onclick=()=>{if(b.dataset.kind===kind)return;kind=b.dataset.kind;activeGroup=groups.find(g=>g.kind===kind&&!g.archived)?.id;selected=null;editing=false;render();$('parents').scrollLeft=0;$('children').scrollLeft=0;});
function setTextMode(on){$('keypad').hidden=on;document.querySelector('.device').classList.toggle('text-mode',on);$('noteDone').hidden=!on;}
function blurNote(){$('note').blur();setTextMode(false);}
$('note').onfocus=()=>setTextMode(true);$('note').onblur=()=>setTextMode(false);$('note').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();blurNote();}};$('noteDone').onclick=blurNote;
$('amountButton').onclick=()=>{blurNote();replaceAmount=true;};
function valueOfExpression(){if(!/^\d+(\.\d*)?([+-]\d+(\.\d*)?)*$/.test(expression))return null;return expression.match(/[+-]?\d+(?:\.\d*)?/g).reduce((sum,n)=>sum+Number(n),0);}
function renderAmount(){const value=valueOfExpression();$('amount').textContent=value===null?expression:(value.toFixed(2));$('amount').style.fontSize=$('amount').textContent.length>9?'38px':'';}
document.querySelectorAll('[data-key]').forEach(b=>b.onclick=()=>{blurNote();const k=b.dataset.key;if(k==='back'){expression=expression.slice(0,-1)||'0';replaceAmount=false;}else if(k==='+'||k==='-'){expression=expression.replace(/[+-]$/,'')+k;replaceAmount=false;}else{if(replaceAmount){expression=k==='.'?'0.':k;replaceAmount=false;}else if(expression.length<15){const last=expression.split(/[+-]/).pop();if(k==='.'&&last.includes('.'))return;if(k!=='.'&&last.includes('.')&&last.split('.')[1].length>=2)return;expression=(expression==='0'&&k!=='.')?k:expression+k;}}renderAmount();});
$('saveEntry').onclick=()=>{const value=valueOfExpression(),info=selectedInfo();if(!info)return announce('先选择一个二级分类');if(value===null||value<=0)return announce('请输入有效金额');announce(`已记下 ¥${value.toFixed(2)} · ${info.child.name}`);replaceAmount=true;};
function openSheet(title,html){blurNote();restoreFocus=document.activeElement;$('appMain').inert=true;$('keypad').hidden=true;$('sheetTitle').textContent=title;$('sheetContent').innerHTML=html;$('overlay').hidden=false;requestAnimationFrame(()=>$('sheetCancel').focus());}
function closeSheet(){$('overlay').hidden=true;$('appMain').inert=false;setTextMode(false);restoreFocus?.focus?.();restoreFocus=null;}
$('sheetCancel').onclick=closeSheet;$('scrim').onclick=closeSheet;
document.addEventListener('keydown',e=>{if($('overlay').hidden)return;if(e.key==='Escape'){e.preventDefault();closeSheet();}if(e.key==='Tab'){const nodes=[...$('sheet').querySelectorAll('button:not([disabled]),input,select')].filter(n=>!n.hidden);const first=nodes[0],last=nodes.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}});
function openSearch(){openSheet('全部分类',`<label class="search-field">${icon('search')}<input id="categorySearch" type="search" placeholder="搜索一级或二级分类" aria-label="搜索分类" autocomplete="off"></label><div id="searchResults"></div>`);$('categorySearch').oninput=renderSearch;renderSearch();requestAnimationFrame(()=>$('categorySearch').focus());}
function renderSearch(){const q=$('categorySearch').value.trim().toLocaleLowerCase();let results='';groups.filter(g=>g.kind===kind&&!g.archived).forEach(g=>{const children=g.children.filter(c=>!c.archived&&(g.name.toLocaleLowerCase().includes(q)||c.name.toLocaleLowerCase().includes(q)));if(children.length)results+=`<section class="search-group"><h3>${escapeHTML(g.name)}</h3><div class="search-grid">${children.map(c=>`<button class="search-result ${selected===c.id?'selected':''}" data-result="${c.id}" data-parent="${g.id}">${escapeHTML(c.name)}</button>`).join('')}</div></section>`;});$('searchResults').innerHTML=results||'<p class="empty">没有找到这个分类</p>';$('searchResults').querySelectorAll('[data-result]').forEach(b=>b.onclick=()=>{activeGroup=b.dataset.parent;selected=b.dataset.result;editing=false;closeSheet();render();requestAnimationFrame(()=>{$('parents').querySelector('.active')?.scrollIntoView({block:'nearest',inline:'nearest'});$('children').querySelector('.selected')?.scrollIntoView({block:'nearest',inline:'nearest'});});});}
$('allCategories').onclick=openSearch;
function openEditor(type,node){
 const isGroup=type.toLowerCase().includes('group'),isNew=type.startsWith('new'),title=isNew?(isGroup?'新增一级分类':'新增二级分类'):(isGroup?'编辑一级分类':'编辑二级分类');
 const parent=group(),used=isGroup?(node?.children.reduce((n,c)=>n+c.used,0)||0):(node?.used||0);
 openSheet(title,`<label class="field-label" for="editName">名称</label><input class="editor-input" id="editName" aria-label="分类名称" value="${escapeHTML(node?.name||'')}" maxlength="18" placeholder="为分类起个名字">${!isGroup?`<label class="field-label" for="editParent">所属一级分类</label><select class="editor-select" id="editParent" aria-label="所属一级分类">${groups.filter(g=>g.kind===kind&&!g.archived).map(g=>`<option value="${g.id}" ${g.id===parent.id?'selected':''}>${escapeHTML(g.name)}</option>`).join('')}</select>`:''}<p class="form-footer">${isNew?'保存后会出现在当前分类中。':used?'改名保留历史关联；归档后不再展示。':'还没有使用过，可以随时整理。'}</p><p id="editError" class="error" role="alert"></p><button id="saveCategory" class="sheet-action">${isNew?'添加分类':'保存修改'}</button>${!isNew?'<button id="archiveCategory" class="quiet-action">归档分类</button>'+(!used?'<button id="deleteCategory" class="quiet-action danger">删除未使用分类</button>':''):''}`);
 $('saveCategory').onclick=()=>{const name=$('editName').value.trim(),destination=!isGroup?groups.find(g=>g.id===$('editParent').value):null;if(!name){$('editError').textContent='名称不能为空';return;}const peers=isGroup?groups.filter(g=>g.kind===kind):destination.children;if(peers.some(c=>c.id!==node?.id&&c.name.toLocaleLowerCase()===name.toLocaleLowerCase())){$('editError').textContent='这里已经有同名分类';return;}const before=structuredClone(groups),oldActive=activeGroup,oldSelected=selected;if(isNew){const id='new-'+crypto.randomUUID();if(isGroup){groups.push({id,name,kind,children:[],archived:false});activeGroup=id;}else{destination.children.push({id,name,icon:'grid',used:0,archived:false});activeGroup=destination.id;if(!editing)selected=id;}}else{node.name=name;if(!isGroup&&destination.id!==parent.id){parent.children=parent.children.filter(c=>c.id!==node.id);destination.children.push(node);activeGroup=destination.id;}}closeSheet();render();if(isNew)requestAnimationFrame(()=>{if(isGroup)$('parents').querySelector('.active')?.scrollIntoView({block:'nearest',inline:'nearest'});else $('children').querySelectorAll('[data-child]')[destination.children.filter(c=>!c.archived).length-1]?.scrollIntoView({block:'nearest',inline:'nearest'});});announce(isNew?'分类已添加':'分类已更新',()=>{groups=before;activeGroup=oldActive;selected=oldSelected;});};
 if(isNew)return;
 const remove=permanent=>{if(isGroup&&groups.filter(g=>g.kind===kind&&!g.archived).length===1){$('editError').textContent='至少保留一个一级分类';return;}const before=structuredClone(groups),oldActive=activeGroup,oldSelected=selected;if(isGroup){if(permanent)groups=groups.filter(g=>g.id!==node.id);else node.archived=true;activeGroup=groups.find(g=>g.kind===kind&&!g.archived).id;}else{if(permanent)parent.children=parent.children.filter(c=>c.id!==node.id);else node.archived=true;}if(!selectedInfo())selected=null;closeSheet();render();announce(permanent?'分类已删除':'分类已归档',()=>{groups=before;activeGroup=oldActive;selected=oldSelected;});};
 $('archiveCategory').onclick=()=>remove(false);if($('deleteCategory'))$('deleteCategory').onclick=()=>remove(true);
}
function chooseMetadata(title,items,selectedText,onSelect){openSheet(title,items.map(value=>`<button class="option" data-option="${escapeHTML(value)}"><span>${escapeHTML(value)}</span>${selectedText===value?icon('check'):''}</button>`).join(''));document.querySelectorAll('[data-option]').forEach(b=>b.onclick=()=>{onSelect(b.dataset.option);closeSheet();});}
$('accountButton').onclick=()=>chooseMetadata('付款账户',['微信','支付宝','现金','银行卡'],$('accountName').textContent,v=>$('accountName').textContent=v);
$('dateButton').onclick=()=>chooseMetadata('记账日期',['今天','昨天','前天'],$('dateName').textContent,v=>$('dateName').textContent=v);
$('closeEntry').onclick=()=>openSheet('清空这笔录入？','<p class="form-footer">金额和备注将清空，分类目录保持不变。</p><button id="clearEntry" class="sheet-action">清空录入</button><button id="keepEntry" class="quiet-action">继续记账</button>')||bindClear();
function bindClear(){$('clearEntry').onclick=()=>{expression='0';selected=null;$('note').value='';closeSheet();render();};$('keepEntry').onclick=closeSheet;}
$('resetDemo').onclick=()=>{groups=structuredClone(initial);kind='expense';activeGroup='food';selected='coffee';editing=false;expression='36';replaceAmount=true;$('note').value='';$('accountName').textContent='微信';$('dateName').textContent='今天';$('toast').hidden=true;closeSheet();render();$('parents').scrollLeft=0;$('children').scrollLeft=0;};
render();

function fitPreview(){document.querySelector('.device').style.zoom=innerWidth>480?String(Math.min(1,Math.max(.65,(innerHeight-40)/824))):'1';}addEventListener('resize',fitPreview);fitPreview();
