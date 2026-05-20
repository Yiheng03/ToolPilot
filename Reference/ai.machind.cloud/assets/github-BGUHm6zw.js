import{ah as j,be as E,am as p,al as H,k as N,an as v,bs as O,c2 as V,F as A,ao as F,j as k,ap as w,bU as L,c3 as y}from"./index-HywmEUgK.js";let S=!1;function T(){if(j&&window.CSS&&!S&&(S=!0,"registerProperty"in(window==null?void 0:window.CSS)))try{CSS.registerProperty({name:"--n-color-start",syntax:"<color>",inherits:!1,initialValue:"#0000"}),CSS.registerProperty({name:"--n-color-end",syntax:"<color>",inherits:!1,initialValue:"#0000"})}catch{}}function $(e){const{heightSmall:i,heightMedium:r,heightLarge:s,borderRadius:a}=e;return{color:"#eee",colorEnd:"#ddd",borderRadius:a,heightSmall:i,heightMedium:r,heightLarge:s}}const I={common:E,self:$},K=p([H("skeleton",`
 height: 1em;
 width: 100%;
 transition:
 --n-color-start .3s var(--n-bezier),
 --n-color-end .3s var(--n-bezier),
 background-color .3s var(--n-bezier);
 animation: 2s skeleton-loading infinite cubic-bezier(0.36, 0, 0.64, 1);
 background-color: var(--n-color-start);
 `),p("@keyframes skeleton-loading",`
 0% {
 background: var(--n-color-start);
 }
 40% {
 background: var(--n-color-end);
 }
 80% {
 background: var(--n-color-start);
 }
 100% {
 background: var(--n-color-start);
 }
 `)]),M=Object.assign(Object.assign({},w.props),{text:Boolean,round:Boolean,circle:Boolean,height:[String,Number],width:[String,Number],size:String,repeat:{type:Number,default:1},animated:{type:Boolean,default:!0},sharp:{type:Boolean,default:!0}}),W=N({name:"Skeleton",inheritAttrs:!1,props:M,setup(e){T();const{mergedClsPrefixRef:i,mergedComponentPropsRef:r}=F(e),s=k(()=>{var n,o;return e.size||((o=(n=r==null?void 0:r.value)===null||n===void 0?void 0:n.Skeleton)===null||o===void 0?void 0:o.size)}),a=w("Skeleton","-skeleton",K,I,e,i);return{mergedClsPrefix:i,style:k(()=>{var n,o;const g=a.value,{common:{cubicBezierEaseInOut:z}}=g,h=g.self,{color:_,colorEnd:x,borderRadius:C}=h;let l;const{circle:d,sharp:P,round:B,width:t,height:c,text:f,animated:R}=e,b=s.value;b!==void 0&&(l=h[L("height",b)]);const u=d?(n=t??c)!==null&&n!==void 0?n:l:t,m=(o=d?t??c:c)!==null&&o!==void 0?o:l;return{display:f?"inline-block":"",verticalAlign:f?"-0.125em":"",borderRadius:d?"50%":B?"4096px":P?"":C,width:typeof u=="number"?y(u):u,height:typeof m=="number"?y(m):m,animation:R?"":"none","--n-bezier":z,"--n-color-start":_,"--n-color-end":x}})}},render(){const{repeat:e,style:i,mergedClsPrefix:r,$attrs:s}=this,a=v("div",O({class:`${r}-skeleton`,style:i},s));return e>1?v(A,null,V(e,null).map(n=>[a,`
`])):a}});export{W as _};
