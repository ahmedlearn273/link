var CACHE="wasla-shell-v1";
var SHELL=["/","/manifest.webmanifest","/translations.js","/icons/icon-192.png","/icons/icon-512.png","/icons/icon-maskable-192.png","/icons/icon-maskable-512.png","/icons/apple-touch-icon.png"];
self.addEventListener("install",function(e){
 e.waitUntil(caches.open(CACHE).then(function(c){return Promise.all(SHELL.map(function(u){return c.add(new Request(u,{cache:"reload"})).catch(function(){})}))}).catch(function(){}).then(function(){return self.skipWaiting()}));
});
self.addEventListener("activate",function(e){
 e.waitUntil(caches.keys().then(function(ks){return Promise.all(ks.filter(function(k){return k.indexOf("wasla-shell-")===0&&k!==CACHE}).map(function(k){return caches.delete(k)}))}).catch(function(){}).then(function(){return self.clients.claim()}));
});
self.addEventListener("push",function(e){
 var d={};
 try{d=e.data?e.data.json():{}}catch(_){try{d={title:e.data.text()}}catch(__){}}
 e.waitUntil(Promise.resolve().then(function(){
  return self.registration.showNotification(d.title||"وصلة",{body:d.body||"",icon:"/icons/icon-192.png",badge:"/icons/badge-96.png",tag:d.tag||undefined,lang:"ar",dir:"rtl",data:d});
 }));
});
self.addEventListener("notificationclick",function(e){
 e.notification.close();
 var d=e.notification.data||{};
 e.waitUntil(self.clients.matchAll({type:"window",includeUncontrolled:true}).then(function(l){
  for(var i=0;i<l.length;i++){
   if("focus" in l[i]){
    try{l[i].postMessage({wasla_nf:{notification_type:d.type||"",request_id:d.request_id||null}})}catch(_){}
    return l[i].focus();
   }
  }
  if(self.clients.openWindow)return self.clients.openWindow("/?wnf="+encodeURIComponent((d.type||"")+"|"+(d.request_id||"")));
 }));
});
self.addEventListener("fetch",function(e){
 var r=e.request;
 if(r.method!=="GET")return;
 var u=new URL(r.url);
 if(u.origin!==self.location.origin)return;
 if(r.mode==="navigate"){
  e.respondWith(fetch(r).then(function(res){var cp=res.clone();if(res.ok)caches.open(CACHE).then(function(c){c.put("/",cp)}).catch(function(){});return res}).catch(function(){return caches.match("/").then(function(m){return m||new Response("offline",{status:503,headers:{"Content-Type":"text/plain;charset=utf-8"}})})}));
  return;
 }
 if(SHELL.indexOf(u.pathname)>-1){
  e.respondWith(fetch(r).then(function(res){var cp=res.clone();if(res.ok)caches.open(CACHE).then(function(c){c.put(r,cp)}).catch(function(){});return res}).catch(function(){return caches.match(r)}));
 }
});
