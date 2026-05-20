/* empty css                  */import{H,$ as P}from"./index-CP4RZoLH.js";import{M as S}from"./index-B3-BI-td.js";import{v as A}from"./v4-C6aID195.js";import{k as K,l as p,I as L,ay as B,p as y,o as k,x as D,q as _}from"./index-HywmEUgK.js";import{_ as z}from"./_plugin-vue_export-helper-DlAUqK2U.js";const V={class:"custom-card-container"},q={key:0,class:"card-left"},J=["src","alt"],O={class:"card-right"},W=["innerHTML"],G=K({__name:"chatCard",props:{backendMarkdown:{}},emits:["card-rendered"],setup(b,{emit:w}){const C=b,R=w,$=p(""),h=p(""),u=p(""),E=p([]),g=S({html:!0,linkify:!0,typographer:!0,breaks:!0,highlight(t,e){return`<pre class="hljs !leading-[0] !mt-2 !overflow-hidden relative border !p-0 rounded-md border-[lcui-border-color]">
    <div class="px-2 py-1 bg-[--lcui-color-accent] border-b border-[--lcui-color-accent-darker] relative flex items-center justify-between">
      <span>${e}</span>
      <div class="flex items-center gap-2">
          <button class="copy-button p-1.5 py-1 text-xs border border-accent-deep rounded-md hover:bg-accent-hover">Copy</button>
      </div>
    </div>
    <div class="!px-2 leading-relaxed py-2"><code>${H.highlightAuto(t).value}</code></div>
    </pre>`}}).use(P,{throwOnError:!1,displayMode:!1,trust:!0,delimiters:"all",mathFence:!0,allowInlineWithSpace:!0}),T=g.renderer.rules.link_open||function(t,e,n,c,a){return a.renderToken(t,e,n)};g.renderer.rules.link_open=function(t,e,n,c,a){const o=t[e],m=o.attrIndex("target");return m<0?(o.attrPush(["target","_blank"]),o.attrPush(["rel","noopener noreferrer"])):o.attrs[m][1]="_blank",T(t,e,n,c,a)};const M=p({}),N=p(!1);(()=>{var o;const t=C.backendMarkdown||"",e=/<left>!\[(.*?)\]\((.*?)\)<\/left>/s,n=t.match(e),c=/<right>([\s\S]*?)<\/right>/s;let a=[];t.match(c)?a=t.match(c):a=t.match(/<card>([\s\S]*?)<\/card>/s),$.value=(n==null?void 0:n[1])||"",h.value=(n==null?void 0:n[2])||"",u.value=((o=a==null?void 0:a[1])==null?void 0:o.trim())||"暂无相关信息"})();const U=t=>{var c;const e=t.match(/<left>!\[(.*?)\]\((.*?)\)<\/left>/),n=t.match(/<right>([\s\S]*?)<\/right>/);return{altText:(e==null?void 0:e[1])||"卡片图片",imgUrl:(e==null?void 0:e[2])||"",rightContent:((c=n==null?void 0:n[1])==null?void 0:c.trim())||"",content:t}};function j(t){let e=(t==null?void 0:t.trim())||"";e=e.replace(/(\*\*[^*]+\*\*)：/g,"$1"),e=e.replace(/<sup>(.*?)<\/sup>/g,"$1");const n=/<card>[\s\S]*?<\/card>/gs;e=e.replace(n,r=>{const s=`card-placeholder-${A().replace(/-/g,"")}`,l=U(r);return M.value[s]={id:s,content:r,imgUrl:l.imgUrl,altText:l.altText,rightContent:l.rightContent},`<div id="${s}" class="card-placeholder"></div>`}),e=e.replace(/\$\$(.+?)\$\$/gs,(r,s)=>`$$${s.replace(/\\\\/g,"\\")}$$`),e=e.replace(new RegExp("(?<!\\\\)\\$(.+?)(?<!\\\\)\\$","g"),(r,s)=>`$${s.replace(/\\\\/g,"\\")}$`);const c=/\(\s*(来源文档编号|来源联网搜索结果)\s*(?:,|：)?\s*([0-9,]+)\s*\)/g,a=[];let o=0;const m=/<sup>\(\s*([0-9,]+)\s*\)<\/sup>/g;e=e.replace(m,(r,s)=>{const l=s.split(",").map(d=>parseInt(d.trim(),10)).filter(d=>!isNaN(d));return l.length===0?r:l==null?void 0:l.map(d=>{const i=`@@SUP_MARKER_${o}@@`;return a.push({placeholder:i,type:1,originIndex:d-1,newIndex:o+1}),o++,i}).join("")}),e=e.replace(c,(r,s,l)=>{const d=s==="来源文档编号"?1:2,i=l.split(",").map(v=>parseInt(v.trim(),10));return i==null?void 0:i.map(v=>{const I=`@@SUP_MARKER_${o}@@`;return a.push({placeholder:I,type:d,originIndex:v-1,newIndex:o+1}),o++,I}).join("")}),E.value=a;let f=a.length;e=e.replace(/<sup>\[\[(\d+)\]\]\((.*?)\)<\/sup>/g,(r,s,l)=>{f++;const d=`@@LINK_MARKER_${f}@@`;return a.push({placeholder:d,type:"link",url:l,newIndex:f}),d});let x=g.render(e);return a.forEach(r=>{let s="";r.type===1||r.type===2?s=`
      <span class="sup-marker"
        data-type-marker="true"
        data-type="${r.type}"
        data-origin-index="${r.originIndex}"
        data-new-index="${r.newIndex}"
        style="color: #0d53ff; cursor: pointer; font-size: 12px; line-height: 0;">
        ${r.newIndex}
      </span>
`:r.type==="link"&&(s=`<sup>
      <span class="sup-marker"
        data-link-marker="true"
        data-index="${r.newIndex}"
        data-url="${r.url}"
        style="color: #0d53ff; cursor: pointer;">
        ${r.newIndex}
      </span>
    </sup>`),x=x.split(r.placeholder).join(s)}),x}L(()=>{u.value&&(u.value=j(u.value),B(()=>{R("card-rendered")}))});const F=()=>{N.value=!0};return(t,e)=>(k(),y("div",V,[h.value?(k(),y("div",q,[_("img",{src:h.value,alt:$.value,class:"card-img",onError:F,loading:"lazy"},null,40,J)])):D("",!0),_("div",O,[_("div",{class:"card-content",innerHTML:u.value},null,8,W)])]))}}),ne=z(G,[["__scopeId","data-v-06365665"]]);export{ne as default};
