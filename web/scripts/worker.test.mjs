import { readFileSync } from "node:fs";
import { expect, test } from "vitest";
import { workerSource } from "./serviceWorker.mjs";

// web/sw.js itself, run with a stand-in for the browser around it: its caches, the network, notifications and the
// app's windows. Playwright can reach a worker's push and its install only partly (offline.spec.ts).

const template = readFileSync(new URL("../sw.js", import.meta.url), "utf8");
const scope = "https://example.test/fitling/";

function key(request) {
  return typeof request === "string" ? new URL(request, scope).href : request.url;
}

/** One build's worker in a browser that already has the caches in `earlier` (name → urls). */
function worker({ files = ["./", "assets/index-new.js"], earlier = {} } = {}) {
  const listeners = {};
  const stores = new Map(Object.entries(earlier).map(([name, urls]) => [name, new Map(urls.map((url) => [key(url), `${name} ${url}`]))]));
  const shown = [];
  const opened = [];
  const windows = [];
  const fetched = [];
  const store = (name) => {
    if (!stores.has(name)) stores.set(name, new Map());
    const entries = stores.get(name);
    return {
      match: async (request) => entries.get(key(request)),
      put: async (request, response) => entries.set(key(request), response),
      addAll: async (requests) => {
        for (const request of requests) {
          fetched.push({ url: key(request), cache: request.cache });
          entries.set(key(request), `network ${key(request)}`);
        }
      },
    };
  };
  const caches = {
    open: async (name) => store(name),
    keys: async () => [...stores.keys()],
    delete: async (name) => stores.delete(name),
    match: async (request, options) => {
      for (const [name, entries] of stores) {
        if (options?.cacheName && options.cacheName !== name) continue;
        if (entries.has(key(request))) return entries.get(key(request));
      }
      return undefined;
    },
  };
  const self = {
    location: new URL(`${scope}sw.js`),
    registration: { scope, showNotification: async (title, options) => shown.push([title, options]) },
    clients: {
      claim: async () => undefined,
      matchAll: async () => windows,
      openWindow: async (url) => opened.push(url),
    },
    skipWaiting: async () => undefined,
    addEventListener: (type, listener) => {
      listeners[type] = listener;
    },
  };
  class ScopedRequest extends Request {
    constructor(input, init) {
      super(typeof input === "string" ? new URL(input, self.location) : input, init);
    }
  }
  const network = async (request, init) => {
    fetched.push({ url: key(request), cache: init?.cache ?? request.cache });
    return `network ${key(request)}`;
  };
  const source = workerSource(template, files);
  new Function("self", "caches", "fetch", "Request", "Response", source)(self, caches, network, ScopedRequest, Response);

  /** Fires an event and waits for what the worker hands to waitUntil or respondWith. */
  async function fire(type, event = {}) {
    const waits = [];
    listeners[type]({ ...event, waitUntil: (promise) => waits.push(promise), respondWith: (promise) => waits.push(promise) });
    return (await Promise.all(waits))[0];
  }
  return { fire, stores, shown, opened, windows, fetched };
}

test("installKeepsFreshCopiesOfThisBuild", async () => {
  const sw = worker();
  await sw.fire("install");
  // Past the browser's own cache: a page from before a deploy would otherwise be kept as this build's page.
  expect(sw.fetched).toEqual([
    { url: scope, cache: "reload" },
    { url: `${scope}assets/index-new.js`, cache: "reload" },
  ]);
});

test("thePageComesFreshFromTheServerAndFromTheDeviceWithoutIt", async () => {
  const sw = worker();
  await sw.fire("install");
  const page = { method: "GET", url: scope, mode: "navigate" };
  expect(await sw.fire("fetch", { request: page })).toBe(`network ${scope}`);
  expect(sw.fetched.at(-1)).toEqual({ url: scope, cache: "no-cache" });
});

test("aPageStillOnTheBuildBeforeKeepsItsFiles", async () => {
  const sw = worker({
    earlier: {
      "fitling-shell-oldest": ["./", "assets/index-oldest.js"],
      "fitling-shell-before": ["./", "assets/index-before.js", "assets/scan-before.js"],
      "fitling-media-before": ["partners/owl.png"],
    },
  });
  await sw.fire("install");
  await sw.fire("activate");
  // The build before stays one round, for a page still open on it; older shells and earlier media go.
  expect([...sw.stores.keys()].filter((name) => !name.startsWith("fitling-media-"))).toEqual(
    expect.arrayContaining(["fitling-shell-before"]),
  );
  expect(sw.stores.has("fitling-shell-oldest")).toBe(false);
  expect(sw.stores.has("fitling-media-before")).toBe(false);
  // That page loads the scanner it had not loaded yet: from its own build, not a 404 of the new site.
  const part = { method: "GET", url: `${scope}assets/scan-before.js`, mode: "cors" };
  expect(await sw.fire("fetch", { request: part })).toBe(`fitling-shell-before assets/scan-before.js`);
});

test("aPushShowsTheNameAndWhatThePartnerSays", async () => {
  const sw = worker();
  await sw.fire("push", { data: { json: () => ({ title: "Uiltje", body: "Nog niets gegeten vandaag?" }) } });
  expect(sw.shown).toEqual([["Uiltje", { body: "Nog niets gegeten vandaag?", icon: "icons/icon-192.png" }]]);
});

test("everyPushShowsSomething", async () => {
  // A browser that gets pushes it never sees may stop sending them (userVisibleOnly).
  const sw = worker();
  await sw.fire("push", {
    data: {
      json: () => {
        throw new SyntaxError("not JSON");
      },
    },
  });
  await sw.fire("push", {});
  expect(sw.shown).toEqual([
    ["Fitling", { icon: "icons/icon-192.png" }],
    ["Fitling", { icon: "icons/icon-192.png" }],
  ]);
});

test("tappingTheReminderOpensTheApp", async () => {
  const sw = worker();
  const closed = [];
  const notification = { close: () => closed.push(true) };
  await sw.fire("notificationclick", { notification });
  expect(sw.opened).toEqual([scope]);
  const focused = [];
  sw.windows.push({ url: `${scope}?tab=partner`, focus: async () => focused.push(true) });
  await sw.fire("notificationclick", { notification });
  expect(focused).toEqual([true]);
  expect(sw.opened).toEqual([scope]);
  expect(closed).toEqual([true, true]);
});
