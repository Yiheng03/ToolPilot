import{_ as l,s as k,g as R,t as F,q as I,a as _,b as E,K as D,z as G,F as y,G as C,H as z,l as P,a1 as H}from"./AiBubbleWidget-D_uLV51g.js";import{p as V}from"./chunk-4BX2VUAB-DywyPqir.js";import{p as W}from"./treemap-GDKQZRPO-BlxmSmMP.js";import"./index-HywmEUgK.js";import"./thumbs-down-DibJFtDK.js";import"./StarFilled-BNyw6g0P.js";import"./index-DLrohc15.js";import"./index-E2jV54TK.js";import"./_getAllKeys-CdiXzuET.js";import"./useRefs-D-VS9VmB.js";import"./index-DffxnjY6.js";import"./copy-BtWgH20-.js";import"./more-gh8X8_fH.js";import"./thumbs-up-D_HK8sYO.js";import"./index-CFXjtozP.js";import"./pick-attrs-C-HgDET8.js";import"./index-DAf5_Huk.js";import"./useBreakpoint-UY2MwH1j.js";import"./responsiveObserve-Bvi3kaM9.js";import"./eagerComputed-N3anUWNp.js";/* empty css                  */import"./index-CP4RZoLH.js";import"./index-B3-BI-td.js";import"./is-CLMHwnDu.js";import"./dateUtil-gcEDVLaI.js";import"./en-US-CfW1V9i1.js";import"./useChatStore-CbeMBiUW.js";import"./index-B6GnrN3J.js";import"./index-lbWbJvMP.js";import"./index-Dt_2MXHU.js";import"./FeedBack-7cKjB-q6.js";import"./const-UVvZYkM0.js";import"./cloneDeep-C0NnvoKV.js";import"./_assignValue-0gyJADKC.js";import"./_getPrototype-lsnZMNpg.js";import"./index-Da8QjsDJ.js";import"./index-BhftCfya.js";import"./TextArea-BO4t51Wu.js";import"./BaseInput-sHK3aqp_.js";import"./_plugin-vue_export-helper-DlAUqK2U.js";import"./QuoteDrawer-CmBJmqbF.js";import"./index-CwTwoBPe.js";import"./chatCard-DFkp6jEw.js";import"./v4-C6aID195.js";import"./purify.es-B9ZVCkUG.js";import"./_getTag-BLhy-212.js";import"./index-C0v6-WMQ.js";import"./dropdown-CI7Fta2Z.js";import"./Dropdown-B9hNMiM5.js";import"./RightOutlined-Crqhby8_.js";import"./move-DGy0l9Tu.js";import"./slide-C9S7fIW9.js";import"./index-Dr5uUJuN.js";import"./collapseMotion-BkNaMiKs.js";import"./DeleteOutlined-BTGAmf8M.js";import"./DownOutlined-BO0odWzY.js";import"./UpOutlined--N4h6-se.js";import"./CollapseItem-BcqVCZT_.js";import"./use-merged-state-BVQW9Tqu.js";import"./happens-in-CM8LO42l.js";import"./_baseEach-CguT9JNW.js";import"./_basePickBy-Bz6zIVMf.js";import"./_baseUniq-BjWIg4QQ.js";import"./_arrayReduce-CrxnWFSq.js";import"./map-nLALYoUI.js";import"./clone-Dj9s3j3Z.js";var h={showLegend:!0,ticks:5,max:null,min:0,graticule:"circle"},w={axes:[],curves:[],options:h},g=structuredClone(w),B=z.radar,j=l(()=>y({...B,...C().radar}),"getConfig"),b=l(()=>g.axes,"getAxes"),q=l(()=>g.curves,"getCurves"),K=l(()=>g.options,"getOptions"),N=l(e=>{g.axes=e.map(t=>({name:t.name,label:t.label??t.name}))},"setAxes"),U=l(e=>{g.curves=e.map(t=>({name:t.name,label:t.label??t.name,entries:X(t.entries)}))},"setCurves"),X=l(e=>{if(e[0].axis==null)return e.map(r=>r.value);const t=b();if(t.length===0)throw new Error("Axes must be populated before curves for reference entries");return t.map(r=>{const a=e.find(o=>{var s;return((s=o.axis)==null?void 0:s.$refText)===r.name});if(a===void 0)throw new Error("Missing entry for axis "+r.label);return a.value})},"computeCurveEntries"),Y=l(e=>{var r,a,o,s,n;const t=e.reduce((i,p)=>(i[p.name]=p,i),{});g.options={showLegend:((r=t.showLegend)==null?void 0:r.value)??h.showLegend,ticks:((a=t.ticks)==null?void 0:a.value)??h.ticks,max:((o=t.max)==null?void 0:o.value)??h.max,min:((s=t.min)==null?void 0:s.value)??h.min,graticule:((n=t.graticule)==null?void 0:n.value)??h.graticule}},"setOptions"),Z=l(()=>{G(),g=structuredClone(w)},"clear"),$={getAxes:b,getCurves:q,getOptions:K,setAxes:N,setCurves:U,setOptions:Y,getConfig:j,clear:Z,setAccTitle:E,getAccTitle:_,setDiagramTitle:I,getDiagramTitle:F,getAccDescription:R,setAccDescription:k},J=l(e=>{V(e,$);const{axes:t,curves:r,options:a}=e;$.setAxes(t),$.setCurves(r),$.setOptions(a)},"populate"),Q={parse:l(async e=>{const t=await W("radar",e);P.debug(t),J(t)},"parse")},tt=l((e,t,r,a)=>{const o=a.db,s=o.getAxes(),n=o.getCurves(),i=o.getOptions(),p=o.getConfig(),m=o.getDiagramTitle(),d=D(t),c=rt(d,p),u=i.max??Math.max(...n.map(f=>Math.max(...f.entries))),x=i.min,v=Math.min(p.width,p.height)/2;et(c,s,v,i.ticks,i.graticule),at(c,s,v,p),M(c,s,n,x,u,i.graticule,p),T(c,n,i.showLegend,p),c.append("text").attr("class","radarTitle").text(m).attr("x",0).attr("y",-p.height/2-p.marginTop)},"draw"),rt=l((e,t)=>{const r=t.width+t.marginLeft+t.marginRight,a=t.height+t.marginTop+t.marginBottom,o={x:t.marginLeft+t.width/2,y:t.marginTop+t.height/2};return e.attr("viewbox",`0 0 ${r} ${a}`).attr("width",r).attr("height",a),e.append("g").attr("transform",`translate(${o.x}, ${o.y})`)},"drawFrame"),et=l((e,t,r,a,o)=>{if(o==="circle")for(let s=0;s<a;s++){const n=r*(s+1)/a;e.append("circle").attr("r",n).attr("class","radarGraticule")}else if(o==="polygon"){const s=t.length;for(let n=0;n<a;n++){const i=r*(n+1)/a,p=t.map((m,d)=>{const c=2*d*Math.PI/s-Math.PI/2,u=i*Math.cos(c),x=i*Math.sin(c);return`${u},${x}`}).join(" ");e.append("polygon").attr("points",p).attr("class","radarGraticule")}}},"drawGraticule"),at=l((e,t,r,a)=>{const o=t.length;for(let s=0;s<o;s++){const n=t[s].label,i=2*s*Math.PI/o-Math.PI/2;e.append("line").attr("x1",0).attr("y1",0).attr("x2",r*a.axisScaleFactor*Math.cos(i)).attr("y2",r*a.axisScaleFactor*Math.sin(i)).attr("class","radarAxisLine"),e.append("text").text(n).attr("x",r*a.axisLabelFactor*Math.cos(i)).attr("y",r*a.axisLabelFactor*Math.sin(i)).attr("class","radarAxisLabel")}},"drawAxes");function M(e,t,r,a,o,s,n){const i=t.length,p=Math.min(n.width,n.height)/2;r.forEach((m,d)=>{if(m.entries.length!==i)return;const c=m.entries.map((u,x)=>{const v=2*Math.PI*x/i-Math.PI/2,f=A(u,a,o,p),O=f*Math.cos(v),S=f*Math.sin(v);return{x:O,y:S}});s==="circle"?e.append("path").attr("d",L(c,n.curveTension)).attr("class",`radarCurve-${d}`):s==="polygon"&&e.append("polygon").attr("points",c.map(u=>`${u.x},${u.y}`).join(" ")).attr("class",`radarCurve-${d}`)})}l(M,"drawCurves");function A(e,t,r,a){const o=Math.min(Math.max(e,t),r);return a*(o-t)/(r-t)}l(A,"relativeRadius");function L(e,t){const r=e.length;let a=`M${e[0].x},${e[0].y}`;for(let o=0;o<r;o++){const s=e[(o-1+r)%r],n=e[o],i=e[(o+1)%r],p=e[(o+2)%r],m={x:n.x+(i.x-s.x)*t,y:n.y+(i.y-s.y)*t},d={x:i.x-(p.x-n.x)*t,y:i.y-(p.y-n.y)*t};a+=` C${m.x},${m.y} ${d.x},${d.y} ${i.x},${i.y}`}return`${a} Z`}l(L,"closedRoundCurve");function T(e,t,r,a){if(!r)return;const o=(a.width/2+a.marginRight)*3/4,s=-(a.height/2+a.marginTop)*3/4,n=20;t.forEach((i,p)=>{const m=e.append("g").attr("transform",`translate(${o}, ${s+p*n})`);m.append("rect").attr("width",12).attr("height",12).attr("class",`radarLegendBox-${p}`),m.append("text").attr("x",16).attr("y",0).attr("class","radarLegendText").text(i.label)})}l(T,"drawLegend");var ot={draw:tt},it=l((e,t)=>{let r="";for(let a=0;a<e.THEME_COLOR_LIMIT;a++){const o=e[`cScale${a}`];r+=`
		.radarCurve-${a} {
			color: ${o};
			fill: ${o};
			fill-opacity: ${t.curveOpacity};
			stroke: ${o};
			stroke-width: ${t.curveStrokeWidth};
		}
		.radarLegendBox-${a} {
			fill: ${o};
			fill-opacity: ${t.curveOpacity};
			stroke: ${o};
		}
		`}return r},"genIndexStyles"),st=l(e=>{const t=H(),r=C(),a=y(t,r.themeVariables),o=y(a.radar,e);return{themeVariables:a,radarOptions:o}},"buildRadarStyleOptions"),nt=l(({radar:e}={})=>{const{themeVariables:t,radarOptions:r}=st(e);return`
	.radarTitle {
		font-size: ${t.fontSize};
		color: ${t.titleColor};
		dominant-baseline: hanging;
		text-anchor: middle;
	}
	.radarAxisLine {
		stroke: ${r.axisColor};
		stroke-width: ${r.axisStrokeWidth};
	}
	.radarAxisLabel {
		dominant-baseline: middle;
		text-anchor: middle;
		font-size: ${r.axisLabelFontSize}px;
		color: ${r.axisColor};
	}
	.radarGraticule {
		fill: ${r.graticuleColor};
		fill-opacity: ${r.graticuleOpacity};
		stroke: ${r.graticuleColor};
		stroke-width: ${r.graticuleStrokeWidth};
	}
	.radarLegendText {
		text-anchor: start;
		font-size: ${r.legendFontSize}px;
		dominant-baseline: hanging;
	}
	${it(t,r)}
	`},"styles"),yr={parser:Q,db:$,renderer:ot,styles:nt};export{yr as diagram};
