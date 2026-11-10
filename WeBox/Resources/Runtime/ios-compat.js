// Keep APK libraries unmodified; adapt advertised capabilities at the iOS boundary.
Widget.capabilities = Object.freeze({protocol:'0.0.7',memoryHls:false,mediaProcessor:false,binary:false,compute:false});
var __originalDefineIOS = WeBox.define;
WeBox = Object.freeze({define:function(source) {
  var unsupported = (source.requires || []).filter(function(x) { return ['html','crypto'].indexOf(x)<0; });
  if (unsupported.length) throw new Error('此内容源需要尚未移植的能力：'+unsupported.join(', '));
  var adapt = function(fn) { return typeof fn !== 'function' ? fn : function(ctx, request) {
    var safe = Object.assign({},ctx,{capabilities:Object.freeze({html:true,crypto:true,memoryHls:false,mediaProcessor:false,binary:false,compute:false})});
    return fn(Object.freeze(safe),request);
  }; };
  var copy = Object.assign({},source);
  ['filters','list','detail','play','search'].forEach(function(k){if(copy[k])copy[k]=adapt(copy[k]);});
  return __originalDefineIOS(copy);
}});
var __transportSyncIOS = __nativeSync;
__nativeSync = function(raw) {
  var call = JSON.parse(raw), p = call.params || {}, method = call.method;
  function enc(name) {
    switch(String(name || 'utf8').toLowerCase()) {
      case 'utf8': case 'utf-8': return CryptoJS.enc.Utf8;
      case 'base64': return CryptoJS.enc.Base64;
      case 'hex': return CryptoJS.enc.Hex;
      case 'latin1': return CryptoJS.enc.Latin1;
      default: throw new Error('不支持的编码：'+name);
    }
  }
  function digest(name) {
    switch(String(name).toUpperCase().replace(/-/g,'')) {
      case 'MD5': return CryptoJS.MD5;
      case 'SHA1': return CryptoJS.SHA1;
      case 'SHA256': return CryptoJS.SHA256;
      case 'SHA384': return CryptoJS.SHA384;
      case 'SHA512': return CryptoJS.SHA512;
      default: throw new Error('不支持的散列算法：'+name);
    }
  }
  var result;
  if(method==='crypto.encode') result=enc(p.to).stringify(enc(p.from).parse(p.text));
  else if(method==='crypto.hash') result=digest(p.algorithm)(enc(p.inputEncoding).parse(p.text)).toString(enc(p.outputEncoding||'hex'));
  else if(method==='crypto.hmac') {
    var algorithm=String(p.algorithm).toUpperCase().replace(/-/g,'');
    var fn=CryptoJS['Hmac'+({MD5:'MD5',SHA1:'SHA1',SHA256:'SHA256',SHA384:'SHA384',SHA512:'SHA512'}[algorithm]||'')];
    if(!fn)throw new Error('不支持的 HMAC 算法');
    result=fn(enc(p.inputEncoding).parse(p.text),enc(p.keyEncoding).parse(p.key)).toString(enc(p.outputEncoding||'hex'));
  } else if(method==='crypto.aes') {
    var mode=String(p.mode||'CBC').toUpperCase(), padding=String(p.padding||'PKCS7').toUpperCase();
    if(!['CBC','ECB','CTR'].includes(mode)||!['PKCS7','NOPADDING','ZEROPADDING'].includes(padding))throw new Error('不支持的 AES 模式或填充');
    var options={iv:enc(p.ivEncoding||'utf8').parse(p.iv),mode:CryptoJS.mode[mode],padding:CryptoJS.pad[({PKCS7:'Pkcs7',NOPADDING:'NoPadding',ZEROPADDING:'ZeroPadding'})[padding]]};
    var key=enc(p.keyEncoding||'utf8').parse(p.key);
    if(p.decrypt)result=CryptoJS.AES.decrypt({ciphertext:enc(p.inputEncoding||'base64').parse(p.text)},key,options).toString(enc(p.outputEncoding||'utf8'));
    else result=CryptoJS.AES.encrypt(enc(p.inputEncoding||'utf8').parse(p.text),key,options).ciphertext.toString(enc(p.outputEncoding||'base64'));
  } else return __transportSyncIOS(raw);
  return JSON.stringify(result);
};
