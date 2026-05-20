import{al as v,am as r,k as C,an as b,ao as x,ap as l,j as a,aq as z}from"./index-HywmEUgK.js";import{t as y}from"./text-Kt-VzrBe.js";const T=v("p",`
 box-sizing: border-box;
 transition: color .3s var(--n-bezier);
 margin: var(--n-margin);
 font-size: var(--n-font-size);
 line-height: var(--n-line-height);
 color: var(--n-text-color);
`,[r("&:first-child","margin-top: 0;"),r("&:last-child","margin-bottom: 0;")]),P=Object.assign(Object.assign({},l.props),{depth:[String,Number]}),j=C({name:"P",props:P,setup(e){const{mergedClsPrefixRef:n,inlineThemeDisabled:t}=x(e),h=l("Typography","-p",T,y,e,n),i=a(()=>{const{depth:o}=e,d=o||"1",{common:{cubicBezierEaseInOut:c},self:{pFontSize:m,pLineHeight:p,pMargin:g,pTextColor:f,[`pTextColor${d}Depth`]:u}}=h.value;return{"--n-bezier":c,"--n-font-size":m,"--n-line-height":p,"--n-margin":g,"--n-text-color":o===void 0?f:u}}),s=t?z("p",a(()=>`${e.depth||""}`),i,e):void 0;return{mergedClsPrefix:n,cssVars:t?void 0:i,themeClass:s==null?void 0:s.themeClass,onRender:s==null?void 0:s.onRender}},render(){var e;return(e=this.onRender)===null||e===void 0||e.call(this),b("p",{class:[`${this.mergedClsPrefix}-p`,this.themeClass],style:this.cssVars},this.$slots)}});export{j as N};
