// Pagination for NoteLibrary's structured document blocks. All assets are already local and decoded.
window.NoteExportPaginate = async function(html, width, height, numbers) {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  document.querySelectorAll('style,link').forEach(el=>el.remove());
  for(const style of parsed.querySelectorAll('style')) document.head.append(style.cloneNode(true));
  document.body.replaceChildren();
  const style=document.createElement('style');
  style.textContent=`html,body{margin:0!important;padding:0!important;background:white!important} .export-page{position:relative;width:${width}px;height:${height}px;padding:64px;box-sizing:border-box;background:white;overflow:hidden} .export-page main{width:100%;max-width:none!important;padding:0!important;margin:0!important;display:flow-root} .export-page main>:first-child{margin-top:0} .export-page table{margin-top:12px;margin-bottom:12px} .export-page footer{position:absolute;bottom:22px;left:64px;right:64px;text-align:center;color:#69716b;font:12px Arial} .export-page figure{margin-bottom:12px} .export-page figcaption{max-height:none}`;
  document.head.append(style);
  // Load the embedded fonts before measuring lines, including KaTeX's non-system faces.
  await document.fonts.ready;
  const limit=height-128, pages=[]; let page,main,checks=0;
  function newPage(carry=true) {
    const trailing=[];
    if(carry && main) while(main.lastElementChild && /^H[123]$/.test(main.lastElementChild.tagName)) trailing.unshift(main.removeChild(main.lastElementChild));
    if(pages.length>=400) throw Error('笔记超过 400 页，请分篇导出。');
    page=document.createElement('div'); page.className='export-page';main=document.createElement('main');page.append(main);document.body.append(page);pages.push(page);
    trailing.forEach(el=>main.append(el));
  }
  function used(){return Math.max(main.scrollHeight,main.getBoundingClientRect().height);}
  function fits(){return used()<=limit+0.25;}
  function hasContent(){return main.children.length>0;}
  async function breathe(){if(++checks%60===0)await new Promise(resolve=>setTimeout(resolve,0));}
  function textLength(node){return node.textContent.length;}
  function slice(node,start,end){
    const walker=document.createTreeWalker(node,NodeFilter.SHOW_TEXT);const range=document.createRange();let offset=0,item,first=false,last=false;
    while(item=walker.nextNode()) {const next=offset+item.length;if(!first&&start<=next){range.setStart(item,Math.max(0,start-offset));first=true;}if(first&&end<=next){range.setEnd(item,Math.max(0,end-offset));last=true;break;}offset=next;}
    const copy=node.cloneNode(false);if(first&&last)copy.append(range.cloneContents());return copy;
  }
  // Only split a paragraph when it cannot fit intact; preserve its links and emphasis.
  async function textBlock(node){
    let rest=node;
    while(textLength(rest)>0){
      main.append(rest);if(fits())return;rest.remove();
      const empty=!hasContent();if(!empty){newPage();main.append(rest);if(fits())return;rest.remove();}
      const length=textLength(rest);let low=0,high=length;
      while(low<high){const mid=Math.ceil((low+high)/2),candidate=slice(rest,0,mid);main.append(candidate);const ok=fits();candidate.remove();if(ok)low=mid;else high=mid-1;}
      if(low===0)throw Error('这段内容无法放入页面，请检查格式。');
      let at=low;if(at<length){const prefix=rest.textContent.slice(0,at),space=prefix.lastIndexOf(' ');if(space>at-35&&space>0)at=space+1;if(/[\uD800-\uDBFF]/.test(rest.textContent[at-1]))at--;}
      const first=slice(rest,0,at);main.append(first);rest=slice(rest,at,length);newPage(false);await breathe();
    }
  }
  async function tableBlock(table){
    const rows=Array.from(table.tBodies).flatMap(body=>Array.from(body.rows));
    const make=()=>{const t=table.cloneNode(false);for(const col of table.querySelectorAll(':scope>colgroup'))t.append(col.cloneNode(true));if(table.tHead)t.append(table.tHead.cloneNode(true));const body=document.createElement('tbody');t.append(body);main.append(t);return [t,body];};
    let [part,body]=make();
    for(const original of rows){
      let row=original.cloneNode(true);body.append(row);
      if(!fits()){
        row.remove();if(!body.rows.length)part.remove();
        newPage();[part,body]=make();body.append(row);
        if(!fits()){
          row.remove();
          // A cell longer than a page is continued with the same column grid and header.
          let cells=Array.from(row.cells).map(cell=>cell.cloneNode(true));
          while(cells.some(cell=>textLength(cell)>0)){
            const segment=row.cloneNode(false);body.append(segment);const tails=[];
            for(const cell of cells){
              const target=cell.cloneNode(false);segment.append(target);const length=textLength(cell);let low=0,high=length;
              while(low<high){const mid=Math.ceil((low+high)/2);target.replaceChildren(...slice(cell,0,mid).childNodes);if(fits())low=mid;else high=mid-1;}
              if(length>0&&low===0)throw Error('表格行无法放入页面，请拆分过长的单元格。');
              target.replaceChildren(...slice(cell,0,low).childNodes);tails.push(slice(cell,low,length));
            }
            cells=tails;if(cells.some(cell=>textLength(cell)>0)){newPage(false);[part,body]=make();}await breathe();
          }
        }
      }
      await breathe();
    }
    if(!rows.length&&!fits()){part.remove();newPage();make();if(!fits())throw Error('表头过长，无法排版。');}
  }
  newPage(false);
  const nodes=Array.from(parsed.querySelector('main').children).flatMap(node=>node.tagName==='SECTION'?Array.from(node.children):[node]);
  for(const node of nodes){
    if(node.tagName==='TABLE'){await tableBlock(node);continue;}
    main.append(node);
    if(node.tagName==='FIGURE') await Promise.all(Array.from(node.querySelectorAll('img')).map(i=>i.decode()));
    if(!fits()){
      node.remove();if(hasContent())newPage();main.append(node);
      if(!fits()){
        if(node.tagName==='P'){node.remove();await textBlock(node);}
        else if(node.tagName==='UL'||node.tagName==='OL'){
          node.remove();for(const li of Array.from(node.children)){const wrap=node.cloneNode(false);wrap.append(li);main.append(wrap);if(!fits()){wrap.remove();if(hasContent())newPage();main.append(wrap);if(!fits()){wrap.remove();const p=document.createElement('p');p.innerHTML='• '+li.innerHTML;await textBlock(p);}}}
        }else throw Error('有一块内容超过页面高度，请拆分后导出。');
      }
    }
    await breathe();
  }
  if(pages.length>1 && !main.children.length){pages.pop().remove();}
  for(const [index,p] of pages.entries()){
    if(numbers){const footer=document.createElement('footer');footer.textContent=`${index+1} / ${pages.length}`;p.append(footer);}
    // Never silently clip content in a supposedly successful export.
    const content=p.querySelector('main');if(content.scrollHeight>limit+1)throw Error('检测到页面溢出，导出未完成。');
  }
  return JSON.stringify(pages.map(p=>{const r=p.getBoundingClientRect();return {x:r.x+window.scrollX,y:r.y+window.scrollY,width:r.width,height:r.height};}));
};
