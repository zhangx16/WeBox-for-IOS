// WeBox Script 1.0 native host. Site algorithms never belong in this file.
(function(){
 const backend=Widget;
 const sync=(method,params)=>backend.callSync(method,params||{});
 const asyncCall=(method,params)=>backend.callAsync(method,params||{});
 const assert={ok(v,message){if(!v)throw Error(message||'脚本数据格式无效');},equal(a,b,message){if(a!==b)throw Error(message||'脚本字段不匹配');},notEqual(a,b,message){if(a===b)throw Error(message||'脚本字段冲突');}};
const own=(x,k)=>Object.prototype.hasOwnProperty.call(x,k);
const object=x=>assert.ok(x && typeof x==='object' && !Array.isArray(x),'object required');
const text=(x,max=1024,empty=false)=>assert.ok(typeof x==='string' && (empty || x.trim().length>0) && x.length<=max,'invalid string');
const unique=xs=>assert.equal(new Set(xs).size,xs.length,'duplicate identity');
function keys(x,allowed){object(x);for(const k of Object.keys(x))assert.ok(allowed.includes(k),'unknown field: '+k);}
function url(x,allowHttp=true){text(x,8192);return sync('url.validate',{url:x,allowHttp:!!allowHttp});}

function value(f,v,allowHttp=true){
 if(v===undefined){assert.ok(!f.required,'required: '+f.key);return v;}
 if(f.type==='boolean')assert.equal(typeof v,'boolean');
 else if(f.type==='number'){
  assert.ok(typeof v==='number'&&Number.isFinite(v));
  if(f.min!==undefined)assert.ok(v>=f.min);if(f.max!==undefined)assert.ok(v<=f.max);
  if(f.step!==undefined){const n=(v-(f.min??0))/f.step;assert.ok(Math.abs(n-Math.round(n))<1e-8);}
 }else{
  assert.equal(typeof v,'string');assert.ok(v.length<=(f.maxLength??(f.type==='url'?8192:1024)));
  if(!v.length){assert.ok(!f.required);if(f.type==='select')assert.ok(f.options.some(o=>o.value===''));return v;}
  if(f.required)assert.ok(v.trim().length>0);
  if(f.type==='select')assert.ok(f.options.some(o=>o.value===v));
  if(f.type==='url')url(v.trim(),allowHttp);
 }
 return f.type==='url'&&v?v.trim():v;
}
function fields(fs,{filter=false,allowHttp=true}={}){
 assert.ok(Array.isArray(fs)&&fs.length<=64);unique(fs.map(f=>f.key));
 for(const f of fs){
  keys(f,['key','label','type','default','required','help','placeholder','maxLength','min','max','step','options','showWhen','sensitive','searchable']);
  assert.ok(/^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(f.key)&&!['constructor','prototype','__proto__'].includes(f.key));text(f.label,80);
  assert.ok((filter?['select']:['text','url','secret','select','number','boolean']).includes(f.type));
  for(const k of ['required','sensitive','searchable'])if(own(f,k))assert.equal(typeof f[k],'boolean');
  for(const k of ['help','placeholder'])if(own(f,k))text(f[k],1024,true);
  if(f.type==='secret')assert.ok(!own(f,'default')&&f.sensitive!==false);
  if(own(f,'maxLength'))assert.ok(Number.isInteger(f.maxLength)&&f.maxLength>0&&f.maxLength<=8192);
  if(f.type==='select'){
   assert.ok(Array.isArray(f.options)&&f.options.length>0&&f.options.length<=500);unique(f.options.map(o=>o.value));
   for(const o of f.options){keys(o,['label','value']);text(o.label,80);text(o.value,1024,true);}
  }
  if(f.type==='number'){
   for(const k of ['min','max','step'])if(own(f,k))assert.ok(typeof f[k]==='number'&&Number.isFinite(f[k]));
   if(own(f,'min')&&own(f,'max'))assert.ok(f.min<=f.max);if(own(f,'step'))assert.ok(f.step>0);
  }
  if(own(f,'default'))value(f,f.default,allowHttp);
  if(f.showWhen){keys(f.showWhen,['key','equals','oneOf']);assert.notEqual(own(f.showWhen,'equals'),own(f.showWhen,'oneOf'));const parent=fs.find(x=>x.key===f.showWhen.key);assert.ok(parent,'unknown dependency');const candidates=own(f.showWhen,'oneOf')?f.showWhen.oneOf:[f.showWhen.equals];assert.ok(Array.isArray(candidates)&&candidates.length>0);for(const c of candidates)value({...parent,required:false},c,allowHttp);}
 }
 const done=new Set(),active=new Set();
 function visit(f){assert.ok(!active.has(f.key),'cyclic dependency');if(done.has(f.key))return;active.add(f.key);if(f.showWhen)visit(fs.find(x=>x.key===f.showWhen.key));active.delete(f.key);done.add(f.key);}
 fs.forEach(visit);return fs;
}
function inputs(fs,supplied={},options={}){
 fields(fs,options);object(supplied);for(const k of Object.keys(supplied))assert.ok(fs.some(f=>f.key===k),'undeclared input');
 const out=Object.create(null),seen=new Set();
 function resolve(f){
  if(seen.has(f.key))return;seen.add(f.key);
  if(f.showWhen){const p=fs.find(x=>x.key===f.showWhen.key);resolve(p);if(!own(out,p.key)||!(own(f.showWhen,'oneOf')?f.showWhen.oneOf:[f.showWhen.equals]).includes(out[p.key]))return;}
  const v=own(supplied,f.key)?supplied[f.key]:f.default;
  const checked=value(f,v,options.allowHttp);if(checked!==undefined)out[f.key]=checked;
 }
 fs.forEach(resolve);return Object.freeze(out);
}
function manifest(s){
 s=Object.assign({allowHttp:true},s);
 keys(s,['api','id','name','version','settings','filters','list','detail','play','search','cache','requires','media','icon','allowHttp']);
 assert.ok(['1.0','1.1'].includes(s.api),'此脚本需要更新的 WeBox 原生接口');assert.ok(/^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$/.test(s.id));text(s.name,80);assert.ok(/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(s.version));
 for(const k of ['list','detail','play'])assert.equal(typeof s[k],'function');
 for(const k of ['filters','search'])if(own(s,k))assert.equal(typeof s[k],'function');
 if(own(s,'allowHttp'))assert.equal(typeof s.allowHttp,'boolean');
 if(s.icon)url(s.icon,s.allowHttp);
 if(s.settings){keys(s.settings,['fields']);fields(s.settings.fields,{allowHttp:s.allowHttp});}
 if(s.cache){keys(s.cache,['list','detail','filters']);for(const v of Object.values(s.cache))assert.ok(Number.isInteger(v)&&v>=0&&v<=86400);}
 if(s.requires){assert.ok(Array.isArray(s.requires));unique(s.requires);for(const c of s.requires)assert.ok(['html','crypto','compute','memoryHls','mediaProcessor','binary'].includes(c));}
 if(s.media){keys(s.media,['request','response']);for(const f of Object.values(s.media))assert.equal(typeof f,'function');}
 return s;
}
function card(x,allowHttp=true){
 keys(x,['id','title','kind','poster','subtitle','rating']);text(x.id);text(x.title,240);assert.ok(['movie','series','live','unknown'].includes(x.kind));
 if(x.poster)url(x.poster,allowHttp);if(own(x,'subtitle'))text(x.subtitle,1024,true);
 if(x.rating){keys(x.rating,['value','scale','label']);assert.ok(Number.isFinite(x.rating.value)&&Number.isFinite(x.rating.scale)&&x.rating.scale>0&&x.rating.value>=0&&x.rating.value<=x.rating.scale);text(x.rating.label,80);}
}
function page(p,seen=new Set(),allowHttp=true){
 keys(p,['items','nextCursor']);assert.ok(Array.isArray(p.items)&&p.items.length<=1000);p.items.forEach(x=>card(x,allowHttp));
 assert.ok(own(p,'nextCursor'));if(p.nextCursor!==null){text(p.nextCursor,2048);assert.ok(!seen.has(p.nextCursor),'repeated cursor');seen.add(p.nextCursor);}return p;
}
function detail(d,id,allowHttp=true){
 keys(d,['id','title','kind','poster','summary','groups']);assert.equal(d.id,id);card(Object.assign({title:id},Object.fromEntries(Object.entries(d).filter(([k])=>!['groups','summary'].includes(k)))),allowHttp);
 if(own(d,'summary'))text(d.summary,65536,true);assert.ok(Array.isArray(d.groups));unique(d.groups.map(g=>g.id));
 for(const g of d.groups){keys(g,['id','name','episodes']);text(g.id);text(g.name,240);assert.ok(Array.isArray(g.episodes));unique(g.episodes.map(e=>e.id));if(d.kind==='movie')assert.ok(g.episodes.length<=1);for(const e of g.episodes){keys(e,['id','name']);text(e.id);text(e.name,240);}}return d;
}
function play(p,source){
 keys(p,['sources']);assert.ok(Array.isArray(p.sources));unique(p.sources.map(s=>s.id));
 for(const s of p.sources){
  keys(s,['id','name','url','manifest','baseUrl','mime','headers','downloadable','processor']);text(s.id);text(s.name,240);assert.notEqual(own(s,'url'),own(s,'manifest'));
  if(own(s,'url'))url(s.url,source.allowHttp);else{assert.ok(source.requires?.includes('memoryHls'));text(s.manifest,2*1024*1024);assert.ok(s.manifest.startsWith('#EXTM3U'));url(s.baseUrl,source.allowHttp);}
  if(s.mime)text(s.mime,120);if(own(s,'downloadable'))assert.equal(typeof s.downloadable,'boolean');
  if(s.headers){object(s.headers);for(const [k,v]of Object.entries(s.headers)){assert.ok(/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(k));text(v,16384,true);assert.ok(!/[\r\n]/.test(v));}}
  if(s.processor){keys(s.processor,['request','response','context']);assert.ok(s.processor.request||s.processor.response);assert.ok(source.requires?.includes('mediaProcessor'));for(const k of ['request','response'])if(s.processor[k])assert.ok(s.processor[k]===k&&typeof source.media?.[k]==='function');object(s.processor.context??{});}
 }return p;
}

let source=null,settings={},ready=false,invocationRefresh=false;
const chains=new Map();
function freeze(v){if(v&&typeof v==='object'){Object.values(v).forEach(freeze);Object.freeze(v);}return v;}
function clone(v){return JSON.parse(JSON.stringify(v));}
function fail(code,message,details){assert.ok(['CONFIG_REQUIRED','AUTH_REQUIRED','NETWORK','RATE_LIMITED','NOT_FOUND','UNSUPPORTED','INVALID_RESPONSE','CANCELLED','TIMEOUT'].includes(code));text(message,800);throw Error('WBX_ERROR:'+JSON.stringify({code,message,sourceId:source?.id||"",details:details||{}}));}
function fieldParams(definitions){return definitions.map(f=>({name:f.key,title:f.label,type:f.type==='select'?'enumeration':f.type,
 required:!!f.required,value:own(f,'default')?String(f.default):undefined,enumOptions:(f.options||[]).map(o=>({title:o.label,value:o.value})),
 belongTo:f.showWhen?[{paramName:f.showWhen.key,value:own(f.showWhen,'equals')?[String(f.showWhen.equals)]:f.showWhen.oneOf.map(String)}]:[],
 description:f.help||'',placeholder:f.placeholder||'',nativeField:Object.assign({},f,{_allowHttp:!!source.allowHttp}),sensitive:f.type==='secret'||!!f.sensitive}));}
function metadata(definitions=[],configured=false){
 if(!source)throw Error('缺少 WeBox.define 注册');
 const globals=fieldParams(source.settings?.fields||[]).map(p=>Object.assign({},p,{name:'__wbSetting_'+p.name,belongTo:p.belongTo.map(d=>Object.assign({},d,{paramName:'__wbSetting_'+d.paramName}))})),params=fieldParams(definitions);
 const cache=source.cache||{};
 const m={id:source.id,title:source.name,version:source.version,requiredVersion:'0.0.7',hostProtocol:'webox',nativeApi:source.api,
 catalogReady:!source.filters||configured,globalParams:globals,detailCacheDuration:cache.detail??60,icon:source.icon||'',
 allowHttp:!!source.allowHttp,modules:[{id:'native-list',title:source.name,functionName:'__wbList',cacheDuration:cache.list??300,
 params:params.concat([{name:'__wb_page',type:'page'}])},{id:'native-play',title:'播放',functionName:'__wbPlay',type:'stream',cacheDuration:0,params:[]}]};
 if(source.search)m.search={id:'native-search',title:'搜索',functionName:'__wbSearch',cacheDuration:0,
 params:[{name:'keyword',title:'关键词',type:'input',required:true},{name:'__wb_page',type:'page'}].concat(params.filter(p=>p.nativeField?.searchable))};
 return m;
}
function typed(definitions,raw){
 const values=Object.create(null);
 for(const f of definitions){if(!own(raw,f.key))continue;let v=raw[f.key];
  if(f.type==='boolean'){if(v===true||v==='true')v=true;else if(v===false||v==='false')v=false;else fail('CONFIG_REQUIRED','请检查'+f.label,{fields:[f.key]});}
  if(f.type==='number'){if(v==='')continue;if(typeof v==='string')v=Number(v);}
  values[f.key]=v;
 }
 try{return inputs(definitions,values,{allowHttp:source.allowHttp});}
 catch(e){fail('CONFIG_REQUIRED','请检查内容源配置或筛选条件');}
}
async function request(method,address,options={}){
 url(address,source.allowHttp);assert.ok(!own(options,'json')||!own(options,'text'),'正文不能同时包含 json 与 text');
 if(method==='GET')assert.ok(!own(options,'json')&&!own(options,'text'),'GET 不接受正文');
 const type=options.responseType||'json';assert.ok(['json','text','base64'].includes(type));
 const timeout=options.timeoutMs??18000;assert.ok(Number.isInteger(timeout)&&timeout>=1&&timeout<=60000);
 const headers=Object.assign({},options.headers||{});
 if(own(options,'json')&&!Object.keys(headers).some(k=>k.toLowerCase()==='content-type'))headers['Content-Type']='application/json';
 const p={url:address,method,headers,params:options.query,timeout:timeout/1000,native:true,httpsOnly:!source.allowHttp,
 decodable:false,base64Data:type==='base64',zlibMode:!!options.decodeContent};
 if(own(options,'json'))p.data=JSON.stringify(options.json);if(own(options,'text'))p.data=options.text;
 const result=await asyncCall('request',p),responseHeaders={};
 url(result.url,source.allowHttp);
 for(const [k,v]of Object.entries(result.headers||{}))if(k.toLowerCase()!=='set-cookie')responseHeaders[k.toLowerCase()]=v;
 let data=result.data;
 if(type==='json'){try{data=JSON.parse(data);}catch(e){fail('INVALID_RESPONSE','接口返回的 JSON 无效');}}
 return {status:result.statusCode,url:result.url,headers:responseHeaders,data};
}
function context(){
 const configured=typed(source.settings?.fields||[],settings);
 return Object.freeze({settings:freeze(clone(configured)),signal:Object.freeze({get aborted(){return !!sync('native.cancelled');},throwIfAborted(){if(sync('native.cancelled'))fail('CANCELLED','操作已取消');}}),
  cache:Object.freeze({get generation(){return sync('native.cache.generation');},seconds:n=>sync('native.cache.seconds',{seconds:n})}),
  capabilities:Object.freeze({html:true,crypto:true,memoryHls:true,mediaProcessor:true,binary:true,compute:backend.capabilities.compute}),
  fail,log(level,message){assert.ok(['debug','info','warn','error'].includes(level));console[level](String(message));},
  url:Object.freeze({resolve:(r,b)=>sync('url.resolve',{url:String(r),base:String(b)}),origin:u=>sync('url.origin',{url:u})}),
  http:Object.freeze({get:(u,o)=>request('GET',u,o),post:(u,o)=>request('POST',u,o)}),
  store:Object.freeze({get:async k=>sync('native.store.get',{key:k}),set:async(k,v)=>{sync('native.store.set',{key:k,value:v});},remove:async k=>{sync('native.store.remove',{key:k});}}),
  html:backend.html,binary:backend.binary,
  crypto:Object.freeze(Object.assign({},backend.crypto,{rsaEncrypt:(t,k)=>sync('crypto.rsa',{text:String(t),key:k}),rsaDecrypt:(t,k)=>sync('crypto.rsa',{text:String(t),key:k,decrypt:true})})),
  compute:Object.freeze({run:o=>asyncCall('compute',{code:o.code,input:o.input,binaries:o.binaries,timeout:(o.timeoutMs||60000)/1000})})
 });
}
let definitions=[],definitionsUntil=0;
async function configure(preserveChains=false){
 const c=context();definitions=source.filters?await source.filters(c,freeze({})):[];fields(definitions,{filter:true,allowHttp:source.allowHttp});fields(definitions.filter(f=>f.searchable),{filter:true,allowHttp:source.allowHttp});
 ready=true;definitionsUntil=Date.now()+sync('native.cache.seconds',{seconds:source.cache?.filters??3600})*1000;if(!preserveChains)chains.clear();return metadata(definitions,true);
}
function entry(x){
 return {id:x.id,type:'url',title:x.title,link:'webox:content:'+encodeURIComponent(x.id),posterPath:x.poster||'',description:x.subtitle||'',
 rating:x.rating?String(x.rating.value):'',ratingSource:x.rating?.label||'',isLive:x.kind==='live'};
}
async function browse(p,search){
 if(!ready || (source.filters && Date.now()>=definitionsUntil))await configure(true);
 const c=context(),all=search?definitions.filter(f=>f.searchable):definitions;
 const selected=typed(all,p),number=Number(p.__wb_page||1);assert.ok(Number.isInteger(number)&&number>0);
 const query=String(p.keyword||'').trim();if(search && (!query||query.length>200))fail('INVALID_RESPONSE','请输入有效搜索词');
 const key=JSON.stringify([search,selected,query,settings]);
 let chain=chains.get(key);if(number===1||!chain){chain=new Map([[1,null]]);if(chains.size>=32)chains.delete(chains.keys().next().value);chains.set(key,chain);}
 if(!chain.has(number))fail('INVALID_RESPONSE','分页状态已失效，请刷新列表');
 const cursor=chain.get(number);if(number>1&&cursor===null)return {items:[],hasMore:false};
 const req=freeze({filters:clone(selected),cursor,limit:30,refresh:invocationRefresh,...(search?{query}:{})});
 const result=await (search?source.search:source.list)(c,req);
 const previous=new Set(Array.from(chain.entries()).filter(([n,v])=>n<=number&&v!==null).map(([n,v])=>v));
 page(result,previous,source.allowHttp);chain.set(number+1,result.nextCursor);
 return {items:result.items.map(entry),hasMore:result.nextCursor!==null,filters:fieldParams(definitions)};
}
function identity(link){
 assert.ok(typeof link==='string'&&link.startsWith('webox:episode:'));
 const data=JSON.parse(decodeURIComponent(link.slice(14)));keys(data,['contentId','groupId','episodeId','live']);
 for(const k of ['contentId','groupId','episodeId'])text(data[k]);return data;
}
globalThis.WeBox=Object.freeze({define(s){
 assert.ok(!source,'只能注册一个 WeBox 内容源');s=manifest(s);
 for(const capability of s.requires||[])assert.ok(capability!=='compute'||backend.capabilities.compute,'缺少独立计算能力');
 source=s;
}});
globalThis.__wbHasSource=()=>!!source;
globalThis.__wbMetadata=()=>JSON.stringify(metadata());
globalThis.__wbSetRefresh=value=>{invocationRefresh=!!value;};
globalThis.__wbSetSettings=raw=>{const next=JSON.parse(raw);if(JSON.stringify(next)!==JSON.stringify(settings)){settings=next;ready=false;chains.clear();}};
globalThis.__wbConfigure=async()=>configure();
globalThis.__wbList=async p=>browse(p,false);
globalThis.__wbSearch=async p=>browse(p,true);
globalThis.__wbDetail=async p=>{
 const id=typeof p==='string'&&p.startsWith('webox:content:')?decodeURIComponent(p.slice(14)):p;
 const d=await source.detail(context(),freeze({id}));detail(d,id,source.allowHttp);
 const names=d.groups.map(g=>g.name);
 return Object.assign(entry(d),{title:d.title||'',overview:d.summary||'',childItems:d.groups.flatMap(g=>g.episodes.map(e=>({id:JSON.stringify([d.id,g.id,e.id]),type:'url',title:e.name,
 episodeGroup:names.filter(n=>n===g.name).length>1?g.name+' · '+g.id:g.name,
 isLive:d.kind==='live',link:'webox:episode:'+encodeURIComponent(JSON.stringify({contentId:d.id,groupId:g.id,episodeId:e.id,live:d.kind==='live'}))})))});
};
globalThis.__wbPlay=async p=>{
 const id=identity(p.link);if(id.live&&p.__wbPurpose==='download')fail('UNSUPPORTED','直播不支持下载');
 const result=await source.play(context(),freeze({contentId:id.contentId,groupId:id.groupId,episodeId:id.episodeId,purpose:p.__wbPurpose||'playback',refresh:p.__weboxRefresh==='true'}));play(result,source);
 return result.sources.filter(s=>p.__wbPurpose!=='download'||s.downloadable!==false).map(s=>{
  const v=Object.assign({},s,{sourceId:s.id,mimeType:s.mime||'',isLive:!!id.live});
  if(s.processor)v.processor={request:s.processor.request?'__wbMediaRequest':'',response:s.processor.response?'__wbMediaResponse':'',context:s.processor.context||{}};
  return v;
 });
};
globalThis.__wbMediaRequest=async input=>{
 const result=await source.media.request(context(),freeze(clone(input)));if(result.url)url(result.url,source.allowHttp);return result;
};
globalThis.__wbMediaResponse=async input=>{
 const result=await source.media.response(context(),freeze(clone(Object.assign({},input,{status:input.statusCode}))));
 return {body:result.body||input.body,mimeType:result.mime||''};
};
})();

if(typeof performance==='undefined')globalThis.performance={now:function(){return Date.now();}};
if(typeof TextEncoder==='undefined')globalThis.TextEncoder=function(){this.encode=function(text){var raw=unescape(encodeURIComponent(String(text))),a=new Uint8Array(raw.length);for(var i=0;i<a.length;i++)a[i]=raw.charCodeAt(i);return a;};};
if(typeof TextDecoder==='undefined')globalThis.TextDecoder=function(){this.decode=function(bytes){var raw='';for(var i=0;i<bytes.length;i++)raw+=String.fromCharCode(bytes[i]);try{return decodeURIComponent(escape(raw));}catch(e){return raw;}};};
