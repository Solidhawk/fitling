// The service worker of Fitling on the web (phase 7): the app and its rules stay on the device, so the app opens
// without a connection, as on the iPhone. The build fills in the files and the build id (scripts/serviceWorker.mjs).
// Supabase and every other host are never touched: what the server says always comes from the server.
const build = "__BUILD__";
const shell = [/*__SHELL__*/];
const shellCache = `fitling-shell-${build}`;
const mediaCache = `fitling-media-${build}`;
/** Partners, exercise sheets and recipe photos: kept once shown (37 MB in all, so never all at once). */
const media = /\/(partners|exercises|recipes)\//;

self.addEventListener("install", (event) => {
  event.waitUntil(
    (async () => {
      await (await caches.open(shellCache)).addAll(shell);
      await self.skipWaiting();
    })(),
  );
});

// A new build takes over at once and the caches of earlier builds go: old rules never meet new code.
self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      for (const name of await caches.keys()) {
        if (name.startsWith("fitling-") && name !== shellCache && name !== mediaCache) await caches.delete(name);
      }
      await self.clients.claim();
    })(),
  );
});

async function fromCache(request, cacheName, keep) {
  const cache = await caches.open(cacheName);
  const kept = await cache.match(request);
  if (kept) return kept;
  const response = await fetch(request);
  if (keep && response.ok) await cache.put(request, response.clone());
  return response;
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin || !url.href.startsWith(self.registration.scope)) return;
  if (request.mode === "navigate") {
    // The page from the server when there is one, so a new build shows; without a connection the one kept.
    event.respondWith(
      fetch(request).catch(async () => (await caches.match(self.registration.scope, { cacheName: shellCache })) ?? Response.error()),
    );
    return;
  }
  event.respondWith(fromCache(request, media.test(url.pathname) ? mediaCache : shellCache, media.test(url.pathname)));
});

// A reminder of the partner (send-reminders): its name as the title, what it says as the text.
self.addEventListener("push", (event) => {
  let message;
  try {
    message = event.data ? event.data.json() : undefined;
  } catch {
    message = undefined;
  }
  if (typeof message?.title !== "string" || typeof message?.body !== "string") return;
  event.waitUntil(self.registration.showNotification(message.title, { body: message.body, icon: "icons/icon-192.png" }));
});

// Tapping it opens the app, or brings it to the front when it is open.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
      const open = windows.find((client) => client.url.startsWith(self.registration.scope));
      if (open) await open.focus();
      else await self.clients.openWindow(self.registration.scope);
    })(),
  );
});
