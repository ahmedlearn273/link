self.addEventListener("install",function(){self.skipWaiting()});
self.addEventListener("activate",function(e){e.waitUntil(self.clients.claim())});
self.addEventListener("push",function(e){
 var d={};
 try{d=e.data?e.data.json():{}}catch(_){try{d={title:e.data.text()}}catch(__){}}
 e.waitUntil(self.clients.matchAll({type:"window",includeUncontrolled:true}).then(function(list){
  for(var i=0;i<list.length;i++){if(list[i].visibilityState==="visible")return}
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
self.addEventListener("fetch",function(){});
