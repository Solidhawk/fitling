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
      // Past the browser's own cache: a page from before a deploy would otherwise be kept as this build's page.
      await (await caches.open(shellCache)).addAll(shell.map((file) => new Request(file, { cache: "reload" })));
      await self.skipWaiting();
    })(),
  );
});

// A new build takes over at once. The shell of the build before stays one round longer, for a page that is still open
// on it and has yet to load a part (the scanner); older shells and the media of earlier builds go. Every file of a
// build has its build in its name or address, so old rules never meet new code.
self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      const before = names.filter((name) => name.startsWith("fitling-shell-") && name !== shellCache).at(-1);
      for (const name of names) {
        if (name.startsWith("fitling-") && name !== shellCache && name !== mediaCache && name !== before) await caches.delete(name);
      }
      await self.clients.claim();
    })(),
  );
});

// Kept answers are found past Vary. A server may send "Vary: Origin" (vite preview does) and the page asks for its
// script and style with crossorigin: matched on Vary, the files kept at install were not found without a connection
// (S51, seen in Chrome 157). A file of a build is the same whoever asks: its build is in its name or address.
const found = { ignoreVary: true };

async function fromCache(request, cacheName, keep) {
  const cache = await caches.open(cacheName);
  // This build first; a page still on the build before finds its own files in that one.
  const kept = (await cache.match(request, found)) ?? (await caches.match(request, found));
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
    // The page from the server when there is one, checked past the browser's cache so a new build shows at once;
    // without a connection the one kept.
    event.respondWith(
      fetch(request, { cache: "no-cache" }).catch(
        async () => (await caches.match(self.registration.scope, { ...found, cacheName: shellCache })) ?? Response.error(),
      ),
    );
    return;
  }
  event.respondWith(fromCache(request, media.test(url.pathname) ? mediaCache : shellCache, media.test(url.pathname)));
});

// A reminder of the partner (send-reminders): its name as the title, what it says as the text. Every push shows
// something: a browser that gets pushes it never sees may stop sending them.
self.addEventListener("push", (event) => {
  let message;
  try {
    message = event.data ? event.data.json() : undefined;
  } catch {
    message = undefined;
  }
  const icon = "icons/icon-192.png";
  const readable = typeof message?.title === "string" && typeof message?.body === "string";
  event.waitUntil(
    readable
      ? self.registration.showNotification(message.title, { body: message.body, icon })
      : self.registration.showNotification("Fitling", { icon }),
  );
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
