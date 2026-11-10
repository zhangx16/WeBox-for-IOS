// WeBox's clean implementation of the public Widget contract.
var module = {exports:{}};
var exports = module.exports;
var Widget = {};
Widget.capabilities=Object.freeze({protocol:'0.0.7',memoryHls:true,mediaProcessor:true,binary:true,
  compute:!!(JSON.parse(__nativeSync(JSON.stringify({method:'runtime.capabilities',params:{}})))||{}).compute});
Widget.binary={
  size:function(handle){return Widget.callSync('binary.size',{handle:handle});},
  read:function(handle,offset,length){var s=atob(Widget.callSync('binary.read',{handle:handle,offset:offset,length:length})),a=new Uint8Array(s.length);for(var i=0;i<s.length;i++)a[i]=s.charCodeAt(i);return a;},
  slice:function(handle,offset,length){var p={handle:handle,offset:offset};if(length!==undefined)p.length=length;return Widget.callSync('binary.slice',p);},
  write:function(handle,offset,bytes){if(!bytes||bytes.length>65536)throw Error('单次写入超过 64 KiB');var s='';for(var i=0;i<bytes.length;i++)s+=String.fromCharCode(bytes[i]);return Widget.callSync('binary.write',{handle:handle,offset:offset,data:btoa(s)});},
  patch:function(handle,patches){return Widget.callSync('binary.patch',{handle:handle,patches:patches.map(function(p){var s='';for(var i=0;i<p.bytes.length;i++)s+=String.fromCharCode(p.bytes[i]);return {offset:p.offset,data:btoa(s)};})});},
  concat:function(handles){return Widget.callSync('binary.concat',{handles:handles});}
};
var callSwiftSync = function(methodName, params) {
  return JSON.parse(__nativeSync(JSON.stringify({method:methodName,params:params||{}})));
};
var callSwiftAsync = function(methodName, params, callback) {
  return __nativeAsync(JSON.stringify({method:methodName,params:params||{}})).then(callback);
};
Widget.callSync = callSwiftSync;
Widget.resolveUrl=function(url,base){return Widget.callSync('url.resolve',{url:String(url),base:String(base)});};
// Shared library is resolved on first use, before or after a module's top-level code.
Object.defineProperty(globalThis,'CryptoJS',{configurable:true,get:function(){
  if(!globalThis.__compatCryptoJS)(0,eval)(__nativeCryptoResource(''));
  var library=globalThis.__compatCryptoJS;
  Object.defineProperty(globalThis,'CryptoJS',{value:library,writable:true,configurable:true});
  return library;
},set:function(value){Object.defineProperty(globalThis,'CryptoJS',{value:value,writable:true,configurable:true});}});
function createCryptoJS(){return globalThis.CryptoJS;}
var require=function(name){if(name==='crypto-js'||name==='CryptoJS')return globalThis.CryptoJS;throw new Error('应用未提供依赖：'+name);};
globalThis.crypto={getRandomValues:function(array){
  if(!ArrayBuffer.isView(array)||array instanceof DataView||array instanceof Float32Array||array instanceof Float64Array)throw new TypeError('需要整数类型数组');
  var bytes=Widget.callSync('crypto.random',{size:array.byteLength});
  new Uint8Array(array.buffer,array.byteOffset,array.byteLength).set(bytes);return array;
}};
Widget.crypto={
  aesEncrypt:function(text,key,iv,options){return Widget.callSync('crypto.aes',Object.assign({},options||{},{text:String(text),key:String(key),iv:String(iv||''),decrypt:false}));},
  aesDecrypt:function(text,key,iv,options){return Widget.callSync('crypto.aes',Object.assign({},options||{},{text:String(text),key:String(key),iv:String(iv||''),decrypt:true}));},
  hash:function(algorithm,text,options){return Widget.callSync('crypto.hash',Object.assign({},options||{},{algorithm:algorithm,text:String(text)}));},
  hmac:function(algorithm,text,key,options){return Widget.callSync('crypto.hmac',Object.assign({},options||{},{algorithm:algorithm,text:String(text),key:String(key)}));},
  md5:function(text){return Widget.callSync('crypto.hash',{algorithm:'MD5',text:String(text)});},
  base64Encode:function(text){return Widget.callSync('crypto.encode',{text:String(text),from:'utf8',to:'base64'});},
  base64Decode:function(text){return Widget.callSync('crypto.encode',{text:String(text),from:'base64',to:'utf8'});}
};
var btoa=function(text){return Widget.callSync('crypto.encode',{text:String(text),from:'latin1',to:'base64'});};
var atob=function(text){return Widget.callSync('crypto.encode',{text:String(text),from:'base64',to:'latin1'});};
function loadJSEncrypt(){return function(){
  this.setPublicKey=function(key){this.key=key;};this.setPrivateKey=function(key){this.key=key;};
  this.encrypt=function(text){try{return Widget.callSync('crypto.rsa',{key:this.key,text:String(text)});}catch(_){return false;}};
  this.decrypt=function(text){try{return Widget.callSync('crypto.rsa',{key:this.key,text:String(text),decrypt:true});}catch(_){return false;}};
};}
globalThis.JSEncrypt=loadJSEncrypt();
Widget.callAsync = async function(methodName, params) {
  var raw = await __nativeAsync(JSON.stringify({method:methodName,params:params||{}}));
  var result = raw;
  if (typeof raw === 'string') { try { result=JSON.parse(raw); } catch (_) {} }
  if (result && result.error) throw new Error(result.error);
  return result;
};
Widget.compute={run:function(options){return Widget.callAsync('compute',options||{});}};
Widget.i18n = function(value) { return typeof value==='string' ? Widget.callSync('i18n',{value:value}) : value; };
Widget.storage = {
  get:function(key){return Widget.callSync('storage.getItem',{key:key});},
  set:function(key,value){Widget.callSync('storage.setItem',{key:key,value:value});},
  remove:function(key){Widget.callSync('storage.removeItem',{key:key});},
  clear:function(){Widget.callSync('storage.clear',{});},
  keys:function(){return Widget.callSync('storage.keys',{})||[];}
};
Widget.sharedCache = {
  get:function(namespace,key){return Widget.callSync('sharedCache.getItem',{namespace:namespace,key:key});},
  set:function(namespace,key,value){Widget.callSync('sharedCache.setItem',{namespace:namespace,key:key,value:value});},
  remove:function(namespace,key){Widget.callSync('sharedCache.removeItem',{namespace:namespace,key:key});},
  keys:function(namespace){return Widget.callSync('sharedCache.keys',{namespace:namespace})||[];}
};
Widget.http = {};
['get','post','put','delete'].forEach(function(name) {
  Widget.http[name] = async function(url, data, options) {
    var hasBody=name==='post'||name==='put';
    var opt=(hasBody?options:data)||{};
    var request={url:url,method:name.toUpperCase(),headers:opt.headers,params:opt.params,
      allow_redirects:opt.allow_redirects,timeout:opt.timeout,decodable:opt.decodable!==false,base64Data:opt.base64Data||false};
    if (hasBody) request.data=data;
    if (name==='get'||name==='post') request.zlibMode=opt.zlibMode||false;
    return Widget.callAsync('request',request);
  };
});
Widget.http.request=function(options){return Widget.callAsync('request',options||{});};
Widget.tmdb={get:function(api,options){return Widget.callAsync('tmdb',{api:api,params:(options||{}).params||{}});}};
Widget.html={load:function(html){return cheerio.load(String(html));}};
var console={};
['log','info','debug','warn','error'].forEach(function(level){
  console[level]=function(){__nativeLog(JSON.stringify({level:level,message:Array.prototype.map.call(arguments,function(x){try{return typeof x==='string'?x:JSON.stringify(x);}catch(_){return String(x);}}).join(' ')}));};
});
function __weboxMetadata() {
  if(typeof __wbHasSource==='function'&&__wbHasSource())return __wbMetadata();
  if(typeof WidgetMetadata!=='object'||!WidgetMetadata) throw new Error('缺少 WidgetMetadata');
  return JSON.stringify(WidgetMetadata);
}
async function __weboxInvoke(name, argsJson) {
  var fn=globalThis[name];
  if(typeof fn!=='function') throw new Error('模块没有定义函数：'+name);
  var result=await fn.apply(globalThis,JSON.parse(argsJson));
  if(result===null||result===undefined) return 'null';
  return typeof result==='string'?result:JSON.stringify(result);
}
