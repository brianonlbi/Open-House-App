/* Caches the form so it opens with no internet. It only ever fetches its own
   files; interview answers live in localStorage and are never sent anywhere. */
var CACHE = "social-history-v1";
var PAGE = "./preschool-social-history.html";
var ASSETS = ["./", PAGE, "./manifest.webmanifest", "./icon.png"];

self.addEventListener("install", function(e){
  e.waitUntil(
    caches.open(CACHE).then(function(c){ return c.addAll(ASSETS); })
      .then(function(){ return self.skipWaiting(); })
  );
});

self.addEventListener("activate", function(e){
  e.waitUntil(
    caches.keys().then(function(keys){
      return Promise.all(keys.map(function(k){
        // Other apps share this origin; only clear our own old versions.
        if(k.indexOf("social-history-") === 0 && k !== CACHE) return caches.delete(k);
      }));
    }).then(function(){ return self.clients.claim(); })
  );
});

// Serve from cache straight away (works offline, no waiting on a weak signal)
// and refresh the cached copy in the background for next time.
self.addEventListener("fetch", function(e){
  var req = e.request;
  if(req.method !== "GET" || new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(
    caches.open(CACHE).then(function(c){
      return c.match(req, {ignoreSearch:true}).then(function(hit){
        var net = fetch(req).then(function(res){
          if(res.ok) c.put(req, res.clone());
          return res;
        });
        if(hit){ net.catch(function(){}); return hit; }
        return net.catch(function(){
          return req.mode === "navigate" ? c.match(PAGE) : Response.error();
        });
      });
    })
  );
});
