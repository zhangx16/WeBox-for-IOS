// Keep APK libraries unmodified; adapt advertised capabilities at the iOS boundary.
// All advertised interfaces below have native implementations (Worker, buffers, proxy).
Widget.capabilities = Object.freeze({protocol:'0.0.7',memoryHls:true,mediaProcessor:true,binary:true,compute:true});
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
    if(String(p.mode||'CBC').toUpperCase()==='GCM')return __transportSyncIOS(raw);
    var mode=String(p.mode||'CBC').toUpperCase(), padding=String(p.padding||(String(p.mode).toUpperCase()==='CTR'?'NOPADDING':'PKCS7')).toUpperCase();
    if(padding==='PKCS5PADDING'||padding==='PKCS7PADDING')padding='PKCS7';
    if(!['CBC','ECB','CTR'].includes(mode)||!['PKCS7','NOPADDING','ZEROPADDING'].includes(padding))throw new Error('不支持的 AES 模式或填充');
    var options={iv:enc(p.ivEncoding||'utf8').parse(p.iv),mode:CryptoJS.mode[mode],padding:CryptoJS.pad[({PKCS7:'Pkcs7',NOPADDING:'NoPadding',ZEROPADDING:'ZeroPadding'})[padding]]};
    var key=enc(p.keyEncoding||'utf8').parse(p.key);
    if(![16,24,32].includes(key.sigBytes))throw new Error('AES 密钥长度必须为 16、24 或 32 字节');
    if(mode!=='ECB'&&options.iv.sigBytes!==16)throw new Error('AES IV 长度必须为 16 字节');
    if(mode==='CTR'&&padding!=='NOPADDING')throw new Error('CTR 模式需要 NoPadding');
    if(p.decrypt)result=CryptoJS.AES.decrypt({ciphertext:enc(p.inputEncoding||'base64').parse(p.text)},key,options).toString(enc(p.outputEncoding||'utf8'));
    else result=CryptoJS.AES.encrypt(enc(p.inputEncoding||'utf8').parse(p.text),key,options).ciphertext.toString(enc(p.outputEncoding||'base64'));
  } else return __transportSyncIOS(raw);
  return JSON.stringify(result);
};
