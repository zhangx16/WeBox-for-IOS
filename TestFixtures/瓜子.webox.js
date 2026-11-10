WeBox.define({
 api:"1.1",id:"dev.webox.native.guazi",name:"瓜子",version:"1.0.3",allowHttp:true,requires:["crypto"],
 cache:{list:120,detail:30,filters:3600},
 async filters(ctx,req){return guaziFilters();},
 async list(ctx,req){return guaziClient(ctx).list(req);},
 async search(ctx,req){return guaziClient(ctx).search(req);},
 async detail(ctx,req){return guaziClient(ctx).detail(req);},
 async play(ctx,req){return guaziClient(ctx).play(req);}
});
let guaziSession;
function guaziClient(ctx){
 const key=JSON.stringify(ctx.settings);
 if(!guaziSession||guaziSession.key!==key)guaziSession={key,client:createGuazi(ctx)};
 return guaziSession.client;
}
function createGuazi(ctx){
 function parseJson(v){return typeof v==='string'?JSON.parse(v):v;}
 async function guaziPost(url,text,options={}){
  ctx.signal.throwIfAborted();
  const r=await ctx.http.post(url,{text,headers:options.headers||{},responseType:'text',timeoutMs:options.timeoutMs||18000});
  return r;
 }
const API_UA = 'okhttp/3.12.0';
const MEDIA_UA = 'Lavf/57.83.100';
const MEDIA_REFERER = 'http://WJiZxLXA2.com/';

const FALLBACK_HOSTS = [
  'https://api.anctjd.com',
  'https://apinew.uozvr.com',
  'https://api.w32z7vtd.com',
  'https://api.6a7nnf7.com',
  'https://api.umygrx3.com',
  'https://api.rmedphk.com'
];

const CONTROL_URLS = [
  'https://api.rqqakqyn.com'
];

const AES_KEY = 'OITxa5OqAYjhswxx';
const AES_IV = 'rCMNwZASNBKZ8mXV';
const DEVICE_OLD_KEY = 'aLFBMWpxBrIDAD1Si/KVvm41';

const RSA_PUBLIC_KEY = `-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDUM5+/y8sPsWkd1/RQS64X259E
UwxFXFE5HlA65MqrxnPs0JqoSRojSDy5QhwvROlaD6TwRQHKMY2OAZ6SnQeUJsCh
TEFIR9qUkwrs3/MVUMxjsv6JS6Oe/juclyJGTgVmDhB55EafXsD0SQYVj/QXXsxR
6ewR5E2kL52yAAD4yQIDAQAB
-----END PUBLIC KEY-----`;

const RSA_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----
MIICdgIBADANBgkqhkiG9w0BAQEFAASCAmAwggJcAgEAAoGAe6hKrWLi1zQmjTT1
ozbE4QdFeJGNxubxld6GrFGximxfMsMB6BpJhpcTouAqywAFppiKetUBBbXwYsYU
1wNr648XVmPmCMCy4rY8vdliFnbMUj086DU6Z+/oXBdWU3/b1G0DN3E9wULRSwcK
ZT3wj/cCI1vsCm3gj2R5SqkA9Y0CAwEAAQKBgAJH+4CxV0/zBVcLiBCHvSANm0l7
HetybTh/j2p0Y1sTXro4ALwAaCTUeqdBjWiLSo9lNwDHFyq8zX90+gNxa7c5EqcW
V9FmlVXr8VhfBzcZo1nXeNdXFT7tQ2yah/odtdcx+vRMSGJd1t/5k5bDd9wAvYdI
DblMAg+wiKKZ5KcdAkEA1cCakEN4NexkF5tHPRrR6XOY/XHfkqXxEhMqmNbB9U34
saTJnLWIHC8IXys6Qmzz30TtzCjuOqKRRy+FMM4TdwJBAJQZFPjsGC+RqcG5UvVM
iMPhnwe/bXEehShK86yJK/g/UiKrO87h3aEu5gcJqBygTq3BBBoH2md3pr/W+hUM
WBsCQQChfhTIrdDinKi6lRxrdBnn0Ohjg2cwuqK5zzU9p/N+S9x7Ck8wUI53DKm8
jUJE8WAG7WLj/oCOWEh+ic6NIwTdAkEAj0X8nhx6AXsgCYRql1klbqtVmL8+95KZ
K7PnLWG/IfjQUy3pPGoSaZ7fdquG8bq8oyf5+dzjE/oTXcByS+6XRQJAP/5ciy1b
L3NhUhsaOVy55MHXnPjdcTX0FaLi+ybXZIfIQ2P4rb19mVq1feMbCXhz+L1rG8oa
t5lYKfpe8k83ZA==
-----END PRIVATE KEY-----`;

const CACHE_KEY = 'guazi_new_auth_v3';

const state = {
  hosts: FALLBACK_HOSTS.slice(),
  hostIndex: 0,
  deviceId: '',
  deviceKey: '',
  token: '',
  tokenId: '',
  registered: false
};

function pad4(num) {
  return ('000' + num.toString(16)).slice(-4);
}

function apiJsonStringify(obj) {
  return JSON.stringify(obj).replace(/[^\x00-\x7F]/g, (ch) => '\\u' + pad4(ch.charCodeAt(0)));
}

function md5Upper(str){return ctx.crypto.md5(str).toUpperCase();}

function base64DecodeToStr(s){try{return ctx.crypto.base64Decode(s);}catch(e){return '';}}
function aesEncryptHex(s){return ctx.crypto.aesEncrypt(s,AES_KEY,AES_IV,{inputEncoding:'utf8',outputEncoding:'hex'}).toUpperCase();}
function aesDecryptHex(s,key,iv){return ctx.crypto.aesDecrypt(s,key,iv,{inputEncoding:'hex',outputEncoding:'utf8'});}
function rsaEncryptText(s){return ctx.crypto.rsaEncrypt(s,RSA_PUBLIC_KEY);}
function rsaDecryptText(s){return ctx.crypto.rsaDecrypt(s,RSA_PRIVATE_KEY);}
function currentHost() {
  return state.hosts[state.hostIndex];
}

function rotateHost() {
  state.hostIndex = (state.hostIndex + 1) % state.hosts.length;
}

function buildHeaders() {
  return {
    'User-Agent': API_UA,
    'code': 'GZ0055',
    'deviceId': state.deviceId,
    'lang': 'zh_cn',
    'Cache-Control': 'no-cache',
    'Content-Type': 'application/x-www-form-urlencoded',
    'Version': '2608011',
    'PackageName': 'com.xf4a1daee2.g3520dce0d.f8a8ed889d20260813',
    'Ver': '3.0.5.2',
    'api-ver': '3.0.5.2',
    'Referer': currentHost()
  };
}

function initDevice() {
  let deviceId = '';
  for (let i = 0; i < 15; i++) {
    deviceId += Math.floor(Math.random() * 10).toString();
  }

  let deviceKey = '';
  const hexChars = '0123456789ABCDEF';
  for (let i = 0; i < 40; i++) {
    deviceKey += hexChars[Math.floor(Math.random() * 16)];
  }

  state.deviceId = deviceId;
  state.deviceKey = deviceKey;
}

async function loadAuth(){
 const saved=await ctx.store.get(CACHE_KEY);
 if(saved && typeof saved==='object'){
  for(const key of ['deviceId','deviceKey','token','tokenId'])if(typeof saved[key]==='string')state[key]=saved[key];
  state.registered=!!saved.registered;
 }
 if(!state.deviceId||!state.deviceKey)initDevice();
}
async function saveAuth(){await ctx.store.set(CACHE_KEY,{deviceId:state.deviceId,deviceKey:state.deviceKey,token:state.token,tokenId:state.tokenId,registered:state.registered});}
async function fetchLatestHosts() {
  for (const controlUrl of CONTROL_URLS) {
    ctx.signal.throwIfAborted();
    try {
      const resp = await guaziPost(
        controlUrl + '/gz/initialize/getApiUrlList?parameter=key',
        '',
        {
          headers: {
            'User-Agent': API_UA,
            'Content-Type': 'application/x-www-form-urlencoded'
          }, timeoutMs:4000
        }
      );

      const body = typeof resp.data === 'string' ? parseJson(resp.data) : resp.data;
      if (!body || Number(body.code) !== 200 || !body.data) continue;

      let decodedStr = base64DecodeToStr(String(body.data));
      if (!decodedStr) {
        try {
          const decrypted=ctx.crypto.aesDecrypt(String(body.data),AES_KEY,AES_IV,{inputEncoding:'base64',outputEncoding:'utf8'});
          if (decrypted) decodedStr = decrypted;
        } catch (e) {ctx.signal.throwIfAborted();}
      }

      if (!decodedStr) continue;

      let parsedData;
      try {
        parsedData = JSON.parse(decodedStr);
      } catch (e) {
        continue;
      }

      let rawHosts = null;
      if (Array.isArray(parsedData) && parsedData.length) {
        rawHosts = parsedData;
      } else if (typeof parsedData === 'object') {
        for (const key of ['list', 'urls', 'data', 'hosts']) {
          if (Array.isArray(parsedData[key]) && parsedData[key].length) {
            rawHosts = parsedData[key];
            break;
          }
        }
      }

      if (rawHosts) {
        const validHosts = rawHosts
          .map((item) => String(item).trim())
          .filter((item) => /^https?:\/\//.test(item));

        if (validHosts.length) {
          state.hosts = validHosts;
          state.hostIndex = 0;
          return;
        }
      }
    } catch (e) {ctx.signal.throwIfAborted();}
  }
}

let hostsReady = false,lastGoodHost='';
async function rememberHost(value){
 const host=currentHost();if(host!==lastGoodHost){await ctx.store.set('guazi_good_host_v1',host);lastGoodHost=host;}
 return value;
}
async function preferKnownHost(){
 const host=await ctx.store.get('guazi_good_host_v1'),index=state.hosts.indexOf(host);
 if(index>=0){state.hostIndex=index;lastGoodHost=host;}
}
async function ensureHosts() {
  if (hostsReady) return;
  const saved=await ctx.store.get('guazi_hosts_v1');
  if(saved&&saved.until>Date.now()&&Array.isArray(saved.hosts)&&saved.hosts.length&&saved.hosts.every(h=>typeof h==='string'&&/^https?:\/\//.test(h))){state.hosts=saved.hosts;await preferKnownHost();hostsReady=true;return;}
  try {
    await fetchLatestHosts();
    await ctx.store.set('guazi_hosts_v1',{hosts:state.hosts,until:Date.now()+6*3600000});
  } catch (e) {ctx.signal.throwIfAborted();}
  await preferKnownHost();
  hostsReady = true;
}

async function applyAuth(authData) {
  const token = String((authData && authData.token) || '');
  if (!token) throw new Error('auth response has no token');
  state.token = token;

  const tokenId = String(authData.app_user_id || authData.token_id || '');
  if (tokenId) state.tokenId = tokenId;

  await saveAuth();
}

async function signUp() {
  const data = await rawApiRequest(
    '/App/Authentication/Device/signUp',
    {
      new_key: state.deviceKey,
      old_key: DEVICE_OLD_KEY,
      phone_type: 1,
      code: ''
    },
    { isAuth: true }
  );
  await applyAuth(data);
  state.registered = true;
  await saveAuth();
}

async function signIn() {
  const data = await rawApiRequest(
    '/App/Authentication/Device/signIn',
    {
      new_key: state.deviceKey,
      old_key: DEVICE_OLD_KEY
    },
    { isAuth: true }
  );
  await applyAuth(data);
  state.registered = true;
  await saveAuth();
}

async function refreshToken() {
  const data = await rawApiRequest(
    '/App/Authentication/Authenticator/refresh',
    {},
    { isAuth: true }
  );
  await applyAuth(data);
}

let tokenReady = false;
async function ensureToken(force) {
  if (!force && tokenReady && state.token) return;

  await loadAuth();
  if(!force&&state.token){tokenReady=true;return;}

  if (!state.token) {
    try {
      await signUp();
    } catch (e) {
      ctx.signal.throwIfAborted();
      await signIn();
    }
    tokenReady=true;return;
  }

  try {
    await refreshToken();
  } catch (e) {
    if (!state.registered) throw e;
    await signIn();
  }

  tokenReady = true;
}

function dictToURI(dict) {
  const parts = [];
  for (const key in dict) {
    parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(dict[key]));
  }
  return parts.join('&');
}

async function rawApiRequest(path, params = {}, options = {}) {
  const isAuth = !!options.isAuth;
  if (!isAuth) {
    await ensureToken(false);
  }
  await ensureHosts();

  const payload = Object.assign({}, params);
  if (payload.token !== undefined) payload.token = state.token;
  if (payload.token_id !== undefined) payload.token_id = state.tokenId;

  const requestKey = aesEncryptHex(apiJsonStringify(payload));
  if (!requestKey) throw new Error('request encrypt failed');

  const encryptedKeys = rsaEncryptText(
    JSON.stringify({
      iv: AES_IV,
      key: AES_KEY
    })
  );

  const timestamp = Math.floor(Date.now() / 1000).toString();
  const signRaw =
    'token_id=' + state.tokenId +
    ',token=' + state.token +
    ',phone_type=1,request_key=' + requestKey +
    ',app_id=1,time=' + timestamp +
    ',keys=' + encryptedKeys +
    '*&zvdvdvddbfikkkumtmdwqppp?|4Y!s!2br';
  const signature = md5Upper(signRaw);

  const formBody = dictToURI({
    token: state.token,
    token_id: state.tokenId,
    phone_type: '1',
    time: timestamp,
    phone_model: 'xiaomi-25031',
    keys: encryptedKeys,
    request_key: requestKey,
    signature: signature,
    app_id: '1',
    ad_version: '1'
  });

  let attempt = 0;
  for (;;) {
    let respData = '';
    let statusCode = 0;
    let reqError = null;

    ctx.signal.throwIfAborted();
    try {
      const resp = await guaziPost(currentHost() + path, formBody, {
        headers: buildHeaders()
      });
      statusCode = resp.status;
      respData = resp.data;
      JSON.parse(respData);
    } catch (e) {
      reqError = e;
    }

    if (reqError || statusCode >= 400) {
      rotateHost();
      attempt++;
      if (attempt < state.hosts.length) continue;
      throw new Error(
        'all hosts failed for ' +
          path +
          (reqError ? ': ' + (reqError.message || reqError) : ' (HTTP ' + statusCode + ')')
      );
    }

    const parsedResp = typeof respData === 'string' ? parseJson(respData) : respData;
    if (parsedResp.code != null && Number(parsedResp.code) !== 200) {
      if (!isAuth && !options.authRetried) {
        options.authRetried = true;
        tokenReady = false;
        try {
          await ensureToken(true);
        } catch (e) {ctx.signal.throwIfAborted();}
        return rawApiRequest(path, params, options);
      }
      throw new Error(
        'code ' +
          parsedResp.code +
          ': ' +
          (parsedResp.msg || parsedResp.message || '') +
          ' @ ' +
          path
      );
    }

    const dataObj = parsedResp.data || {};
    if (!dataObj.response_key) {
      if (dataObj.list || dataObj.vodInfo) return await rememberHost(dataObj);
      throw new Error('response missing response_key @ ' + path);
    }

    let aesKey = AES_KEY;
    let aesIv = AES_IV;
    if (dataObj.keys) {
      const decryptedKeyJson = rsaDecryptText(dataObj.keys);
      if (decryptedKeyJson) {
        try {
          const keyObj = parseJson(decryptedKeyJson);
          if (keyObj.key) aesKey = keyObj.key;
          if (keyObj.iv) aesIv = keyObj.iv;
        } catch (e) {ctx.signal.throwIfAborted();}
      }
    }

    const decryptedPayload = aesDecryptHex(dataObj.response_key, aesKey, aesIv);
    return await rememberHost(JSON.parse(decryptedPayload));
  }
}


 function number(cursor){
  if(cursor===null)return 1;
  if(typeof cursor!=="string"||!/^([1-9]\d*)$/.test(cursor)||!Number.isSafeInteger(Number(cursor)))ctx.fail("INVALID_RESPONSE","分页游标无效");
  return Number(cursor);
 }
 function card(item){
  if(item.vod_id==null||!item.vod_name)ctx.fail("INVALID_RESPONSE","目录格式无效");
  return {id:String(item.vod_id),title:String(item.vod_name),poster:item.vod_pic||"",subtitle:item.new_continue||"",kind:"unknown"};
 }
 function page(res,n,size){
  if(!Array.isArray(res.list))ctx.fail("INVALID_RESPONSE","列表格式无效");
  const total=Number(res.total),hasTotal=res.total!=null&&res.total!==''&&Number.isFinite(total)&&total>=0;
  return {items:res.list.map(card),nextCursor:(hasTotal?n*size<total:res.list.length>=size)?String(n+1):null};
 }
 async function list(req){
  const f=req.filters||{},category=f.category||'hot',n=number(req.cursor);
  if(!TAB_IDS.includes(category))ctx.fail("INVALID_RESPONSE","分类无效");
  const type=f['type_'+category];
  return page(await rawApiRequest('/App/IndexList/indexList',{
   area:f.area||'0',year:f.year||'0',sort:f.sort||(category==='hot'?'d_hits':'d_id'),pageSize:'30',page:String(n),tid:type|| (category==='hot'?'0':category)
  }),n,30);
 }
 async function search(req){
  const query=String(req.query||'').trim();if(!query)return {items:[],nextCursor:null};
  const n=number(req.cursor),res=await rawApiRequest('/App/Index/findMoreVod',{keywords:query,order_val:'1',page:String(n)});
  // Upstream search does not declare page size. An extra empty-page request is preferable to losing results.
  if(!Array.isArray(res.list))ctx.fail("INVALID_RESPONSE","搜索格式无效");
  return {items:res.list.map(card),nextCursor:res.list.length?String(n+1):null};
 }
 async function tracks(id){
  if(typeof id!=='string'||!/^\d+$/.test(id))ctx.fail('NOT_FOUND','影片标识无效');
  const result=await rawApiRequest('/App/Resource/Vurl/show',{vurl_cloud_id:'2',vod_d_id:id});
  if(!Array.isArray(result.list))ctx.fail('INVALID_RESPONSE','选集格式无效');return result;
 }
 function episodeRows(items){
  const seen=new Set();return items.map(x=>{const id=String(x.title||'').trim();if(!id||seen.has(id))ctx.fail('INVALID_RESPONSE','源站选集标识缺失或重复');seen.add(id);return {id,name:id};});
 }
 async function detail(req){
  const result=await tracks(req.id),info=result.vodInfo||{};
  return {id:req.id,...(typeof info.vod_name==='string'&&info.vod_name.trim()?{title:info.vod_name.trim()}:{}),kind:'unknown',poster:info.vod_pic||'',summary:info.vod_content||'',
   groups:[{id:'main',name:'默认线路',episodes:episodeRows(result.list)}]};
 }
 async function play(req){
  if(req.groupId!=='main'||typeof req.episodeId!=='string'||!req.episodeId)ctx.fail('NOT_FOUND','选集无效');
  const result=await tracks(req.contentId),episode=result.list.find(x=>String(x.title)===req.episodeId);
  episodeRows(result.list);
  if(!episode||!episode.play)ctx.fail('NOT_FOUND','选集已变化');
  const qualities=['8k','4k','2160','1440','1080','720','480'],play=episode.play;
  const quality=qualities.find(k=>play[k])||Object.keys(play)[0];
  if(!quality)return {sources:[]};
  const params=Object.create(null),raw=String(play[quality].param||'');
  for(const pair of raw.split('&')){const i=pair.indexOf('=');if(i>0){const k=pair.slice(0,i);if(!['__proto__','prototype','constructor'].includes(k))params[k]=pair.slice(i+1);}}
  params.resolution=quality;
  const data=await rawApiRequest('/App/Resource/VurlDetail/showOne',params);
  if(!data.url)ctx.fail('INVALID_RESPONSE','播放地址缺失');
  return {sources:[{id:'main',name:'默认线路',url:String(data.url).trim(),headers:{'User-Agent':MEDIA_UA,'Referer':MEDIA_REFERER}}]};
 }
 return {list,search,detail,play};
}
function makeYearFilter() {
  const values = [{ n: '全部', v: '0' }];
  for (let year = new Date().getFullYear(); year >= 1900; year--) {
    values.push({ n: String(year), v: String(year) });
  }

  return {
    key: 'year',
    name: '年份',
    value: values
  };
}

const AREA_FILTER = {
  key: 'area',
  name: '地区',
  value: [
    { n: '全部', v: '0' },
    { n: '大陆', v: '大陆' },
    { n: '香港', v: '香港' },
    { n: '台湾', v: '台湾' },
    { n: '美国', v: '美国' },
    { n: '韩国', v: '韩国' },
    { n: '日本', v: '日本' },
    { n: '英国', v: '英国' },
    { n: '法国', v: '法国' },
    { n: '泰国', v: '泰国' },
    { n: '印度', v: '印度' },
    { n: '其他', v: '其他' }
  ]
};

const SORT_FILTER = {
  key: 'sort',
  name: '排序',
  value: [
    { n: '最新入库', v: 'd_id' },
    { n: '热度优先', v: 'd_hits' },
    { n: '评分优先', v: 'd_score' }
  ]
};

const TYPE_FILTERS = {
  '1': { key: 'type', name: '类型', value: [
    { n: '全部', v: '0' }, { n: '动作', v: '5' }, { n: '喜剧', v: '6' },
    { n: '爱情', v: '7' }, { n: '科幻', v: '8' }, { n: '恐怖', v: '9' },
    { n: '剧情', v: '10' }, { n: '战争', v: '11' }, { n: '悬疑', v: '29' }
  ] },
  '2': { key: 'type', name: '类型', value: [
    { n: '全部', v: '0' }, { n: '国产', v: '12' }, { n: '香港', v: '13' },
    { n: '台湾', v: '14' }, { n: '欧美', v: '15' }, { n: '日本', v: '16' },
    { n: '韩国', v: '17' }, { n: '海外', v: '18' }, { n: '泰国', v: '19' }
  ] },
  '3': { key: 'type', name: '类型', value: [
    { n: '全部', v: '0' }, { n: '大陆', v: '22' }, { n: '日韩', v: '24' }
  ] },
  '4': { key: 'type', name: '类型', value: [
    { n: '全部', v: '0' }, { n: '中国', v: '30' }, { n: '日本', v: '31' },
    { n: '欧美', v: '33' }
  ] }
};

const TAB_IDS = ['hot', '1', '2', '4', '3', '64', '74', '33'];
const filterList = {};
TAB_IDS.forEach((tabId) => {
  filterList[tabId] = [...(TYPE_FILTERS[tabId] ? [TYPE_FILTERS[tabId]] : []), AREA_FILTER, makeYearFilter(), SORT_FILTER];
});


function guaziFilters(){
 const categories=[['热门','hot'],['电影','1'],['电视剧','2'],['动漫','4'],['综艺','3'],['短剧','64'],['漫剧','74'],['欧美动漫','33']];
 const fields=[{key:'category',label:'分类',type:'select',default:'hot',options:categories.map(([label,value])=>({label,value}))}];
 function field(group,key,condition){return {key,label:group.name,type:'select',default:group.key==='sort'?'d_id':'',options:group.value.map(o=>({label:o.n,value:o.v==='0'?'':o.v})),...(condition?{showWhen:condition}:{})};}
 for(const key of Object.keys(TYPE_FILTERS))fields.push(field(TYPE_FILTERS[key],'type_'+key,{key:'category',equals:key}));
 fields.push(field(AREA_FILTER,'area'),field(makeYearFilter(),'year'),field(SORT_FILTER,'sort'));return fields;
}
