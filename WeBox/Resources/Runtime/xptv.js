// Compatibility host for the getConfig/getCards/getTracks/getPlayinfo contract.
function __xptvAdLabel(text){return /^\s*[\[【(（]\s*(?:AD|ADS|广告|廣告|广告位|廣告位)\s*[\]】)）]/i.test(String(text));}
function __xptvAdItem(item){
  var flag=function(value){return value===true||value===1||value==='1';};
  return flag(item.is_ad)||flag(item.isAd)||/^(?:ad|advertisement)$/i.test(String(item.type||''))||__xptvAdLabel(item.vod_name||item.title||item.name||'');
}
function createCheerio(){return globalThis.cheerio;}
function argsify(value){return typeof value==='string'?(value?JSON.parse(value):{}):(value||{});}
function jsonify(value){return JSON.stringify(value);}
function dictToURI(value){return Object.keys(value).map(function(key){return encodeURIComponent(key)+'='+encodeURIComponent(value[key]);}).join('&');}
var $config_str='{}',__xptvNotice='',__xptvReady='',__xptvPending=null,__xptvId='',__xptvApp=null,__xptvResponse=null,__xptvGeneration=0;
var $cache={get:function(key){return Widget.storage.get(key);},set:function(key,value){return Widget.storage.set(key,value);},remove:function(key){return Widget.storage.remove(key);}};
function $print(value){console.log(value);}
var $utils={toastInfo:function(message){__xptvNotice=String(message);},toastError:function(message){__xptvNotice=String(message);},toastSuccess:function(message){__xptvNotice=String(message);}};
var $fetch={};
function __xptvResolveUrl(url,config){
  if(/^https?:\/\//i.test(String(url)))return String(url);
  var app=config||(__xptvApp?__xptvApp():{})||{};
  if(!app.site)throw new Error('相对请求地址需要脚本提供 site');
  return Widget.resolveUrl(url,app.site);
}
['get','post','put','delete','head'].forEach(function(method){
  $fetch[method]=async function(url,data,options){
    var body=method==='post'||method==='put',opt=(body?options:data)||{};
    var response=await Widget.http.request({url:__xptvResolveUrl(url),method:method.toUpperCase(),data:body?data:undefined,
      params:opt.params,headers:opt.headers||{},timeout:opt.timeout||20,allow_redirects:opt.allow_redirects,decodable:false,base64Data:opt.base64Data});
    __xptvResponse={status:response.statusCode,challenge:typeof response.data==='string'&&/cf-chl-|SafeLineChallenge|<title>\s*Just a moment/i.test(response.data)};
    return {status:response.statusCode,statusCode:response.statusCode,data:response.data,headers:response.headers,url:response.url};
  };
});
// A messaging/deep-link destination is navigation, not a video category. Unknown
// HTTP hosts and ext IDs are retained; multi-site sources must keep working.
function __xptvIsContentTab(tab,config){
  if(__xptvAdItem(tab))return false;
  var url=(tab.ext||{}).url||tab.url;
  if(typeof url!=='string')return true;
  if(/^(?:tg|mailto|tel|sms|weixin|whatsapp|intent|market|javascript):/i.test(url))return false;
  var absolute;try{absolute=__xptvResolveUrl(url,config);}catch(_){return true;}
  var match=/^https?:\/\/(?:[^\/@]+@)?([^\/:?#]+)/i.exec(absolute);
  var host=match?match[1].toLowerCase().replace(/^www\./,''):'';
  return ['t.me','telegram.me','telegram.dog','line.me','wa.me','chat.whatsapp.com','discord.gg'].indexOf(host)<0;
}
function __xptvMetadata(config,ready){
  var tabs=(Array.isArray(config.tabs)?config.tabs:[]).filter(function(tab){return __xptvIsContentTab(tab,config);});
  var options=tabs.map(function(tab){return {title:String(tab.name||tab.title||'分类'),value:JSON.stringify(tab.ext||{id:tab.id})};});
  var metadata={id:__xptvId,title:String(config.title||'JS 内容源'),version:String(config.ver||config.version||'1'),requiredVersion:'0.0.1',
    site:String(config.site||''),hostProtocol:'xptv',hostAdapterVersion:4,catalogReady:!!ready,globalParams:[{name:'__xptv_config',title:'脚本配置（JSON）',type:'constant',value:'{}'}],
    modules:[{id:'browse',title:'浏览',functionName:'compatBrowse',cacheDuration:120,params:[{name:'category',title:'分类',type:'enumeration',enumOptions:options},{name:'page',type:'page'},{name:'offset',type:'offset'}]}]};
  if(typeof search==='function')metadata.search={id:'search',title:'搜索',functionName:'compatSearch',cacheDuration:60,params:[{name:'keyword',type:'input'},{name:'page',type:'page'}]};
  return metadata;
}
function __weboxXptvAttach(id,app){
  __xptvId=id;__xptvApp=app;
  var config=app()||{};
  WidgetMetadata=__xptvMetadata(config,false);
}
async function __weboxXptvConfigure(params){
  var text=(params||{}).__xptv_config||'{}';
  argsify(text);
  if(__xptvReady===text)return WidgetMetadata;
  if(__xptvPending)return await __xptvPending;
  var generation=__xptvGeneration;
  var work=(async function(){
    $config_str=text;__xptvNotice='';__xptvResponse=null;
    var result=await getConfig();
    if(generation!==__xptvGeneration)throw new Error('旧分类请求已取消');
    if(!result)throw new Error(__xptvNotice||'脚本没有返回分类配置，请检查脚本配置或稍后重试');
    var config=argsify(result);
    if(!Array.isArray(config.tabs)||!config.tabs.length){
      if(__xptvResponse&&__xptvResponse.status>=400)throw new Error('分类请求失败（HTTP '+__xptvResponse.status+'），请检查网络或稍后重试');
      if(__xptvResponse&&__xptvResponse.challenge)throw new Error('分类页面需要网站验证，暂未读取到分类');
      throw new Error(__xptvNotice||'脚本暂未返回可浏览分类，请检查配置或网络后重试');
    }
    var metadata=__xptvMetadata(config,true);
    if(!metadata.modules[0].params[0].enumOptions.length)throw new Error('脚本返回的分类只有站外入口，暂无可浏览片单');
    WidgetMetadata=metadata;__xptvReady=text;
    return WidgetMetadata;
  })();
  __xptvPending=work;
  try{return await work;}finally{if(__xptvPending===work)__xptvPending=null;}
}
function __weboxXptvCancel(){
  __xptvGeneration++;
  if(__xptvPending){__xptvPending=null;__xptvResponse=null;__xptvReady='';}
}
function __xptvItems(raw){
  if(raw===null||raw===undefined)throw new Error(__xptvNotice||'脚本未返回列表，请稍后重试');
  var result=argsify(raw),rows=Array.isArray(result)?result:result.list;
  if(!Array.isArray(rows))throw new Error('脚本返回的列表格式不正确');
  var items=rows.filter(function(item){return !__xptvAdItem(item);}).map(function(item){return {id:String(item.vod_id||item.id||JSON.stringify(item.ext||{})),type:'detail',title:item.vod_name||item.title||'未命名影片',
    posterPath:item.vod_pic||item.poster||'',description:item.vod_remarks||'',overview:item.vod_content||'',isLive:item.isLive===true||item.mediaType==='live'||(__xptvApp&&__xptvApp().mediaType==='live'),link:JSON.stringify(item.ext||{id:item.vod_id})};});
  var rawCount=Number.isInteger(result.rawCount)&&result.rawCount>=rows.length?result.rawCount:rows.length;
  var page={items:items,hasMore:typeof result.hasMore==='boolean'?result.hasMore:rawCount>0,rawCount:rawCount};
  if(Array.isArray(result.filter))page.filters=result.filter.filter(function(group){return group&&typeof group.key==='string'&&Array.isArray(group.value);}).map(function(group){
    var choices=group.value.filter(function(option){return option&&option.v!==undefined;}).map(function(option){return {title:String(option.n||option.v),value:String(option.v)};});
    return {name:'__xptv_filter:'+group.key,title:String(group.name||group.key),type:'enumeration',enumOptions:choices,value:group.default===undefined?(choices[0]||{}).value:String(group.default)};
  });
  return page;
}
async function compatBrowse(params){
  await __weboxXptvConfigure(params);
  var category=params.category;
  if(!category)category=WidgetMetadata.modules[0].params[0].enumOptions[0].value;
  var ext;try{ext=argsify(category);}catch(_){ext={id:category};}
  if(typeof ext!=='object')ext={id:category};
  var filters=Object.assign({},ext.filters||{});
  Object.keys(params).forEach(function(key){if(key.indexOf('__xptv_filter:')===0)filters[key.slice(14)]=params[key];});
  return __xptvItems(await getCards(Object.assign({},ext,{page:Number(params.page||1),offset:Number(params.offset||0),filters:filters})));
}
async function compatSearch(params){
  await __weboxXptvConfigure(params);
  if(typeof search!=='function')throw new Error('这个脚本没有提供搜索');
  return __xptvItems(await search({text:params.keyword,page:Number(params.page||1)}));
}
async function loadDetail(link){
  if(link.indexOf('compat-play:')===0)return [{id:link,type:'url',title:'播放',link:link}];
  if(!__xptvReady)await __weboxXptvConfigure({__xptv_config:$config_str});
  var raw=await getTracks(argsify(link));
  if(raw===undefined||raw===null)throw new Error(__xptvNotice||'脚本未返回播放列表');
  var result=argsify(raw),groups=Array.isArray(result)?result:result.list;
  if(!Array.isArray(groups))throw new Error('脚本返回的播放列表格式不正确');
  var children=[];
  groups.forEach(function(group){(group.tracks||[]).forEach(function(track){
    var ext=JSON.stringify(track.ext||{}),title=String(track.name||track.title||'播放');
    children.push({id:ext,type:'url',title:(groups.length>1?String(group.title||'线路')+' · ':'')+title,link:'compat-play:'+ext});
  });});
  return children;
}
async function loadResource(params){
  if(!__xptvReady)await __weboxXptvConfigure({__xptv_config:$config_str});
  var raw=String(params.link||params.id||'').replace(/^compat-play:/,'');
  var result=argsify(await getPlayinfo(argsify(raw)));
  var urls=result.urls||(result.url?[result.url]:[]);
  return urls.map(function(url,index){return {name:(result.names||[])[index]||'线路 '+(index+1),url:url,mimeType:result.mimeType||'',isLive:result.isLive===true||(__xptvApp&&__xptvApp().mediaType==='live'),headers:Array.isArray(result.headers)?(result.headers[index]||{}):(result.headers||{})};});
}
