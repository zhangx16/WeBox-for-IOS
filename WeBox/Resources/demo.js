WidgetMetadata = {
  id: "dev.webox.demo", title: "公开示例", version: "1.0.1", requiredVersion: "0.0.1",
  description: "用公开演示视频体验列表、搜索和播放", author: "WeBox",
  detailCacheDuration: 0,
  modules: [
    {id:"library", title:"示例视频", functionName:"loadList", cacheDuration:300,
      params:[{name:"group",title:"内容分类",type:"enumeration",enumOptions:[{title:"全部",value:"all"},{title:"短片",value:"short"}]}]},
    {id:"loadResource",title:"播放线路",functionName:"loadResource",type:"stream",cacheDuration:0,params:[]}
  ],
  search: {id:"search",title:"搜索",functionName:"search",params:[{name:"keyword",title:"关键词",type:"input"}]}
};
var demoItems = [{id:"bunny",type:"url",title:"Big Buck Bunny",
  description:"Blender Foundation 开放电影 · 公开测试视频",link:"demo:bunny",
  videoUrl:"https://storage.googleapis.com/exoplayer-test-media-0/BigBuckBunny_320x180.mp4"}];
async function loadList(params) { return demoItems; }
async function search(params) { var word=String(params.keyword||"").toLowerCase(); return demoItems.filter(function(x){return x.title.toLowerCase().indexOf(word)>=0;}); }
async function loadDetail(link) { return demoItems.find(function(x){return x.link===link;}) || demoItems[0]; }
async function loadResource(params) { var x=await loadDetail(params.link); return [{name:"公开测试线路",url:x.videoUrl,sourceDescription:x.description,headers:{}}]; }
