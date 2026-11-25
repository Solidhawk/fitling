import type { Page } from "./fixtures";

// A push service for the browser tests (web phase 7): Playwright has none. Used by reminders.spec.ts and the audit.

export type Fake = { refuse?: boolean; noPush?: boolean };

/**
 * A push service in the page. What the browser would keep, the permission and the subscription, survives a reload
 * (sessionStorage), as it does in a real browser.
 */
export async function fakePush(page: Page, fake: Fake = {}) {
  await page.addInitScript((fake: Fake) => {
    if (fake.noPush) {
      delete (window as { PushManager?: unknown }).PushManager;
      return;
    }
    type Kept = { permission: NotificationPermission; endpoint?: string; key?: number[] };
    const read = (): Kept => JSON.parse(sessionStorage.getItem("e2e.push") ?? '{"permission":"default"}') as Kept;
    const write = (kept: Kept) => sessionStorage.setItem("e2e.push", JSON.stringify(kept));
    const subscription = (kept: Kept) =>
      kept.endpoint === undefined
        ? null
        : {
          endpoint: kept.endpoint,
          options: { applicationServerKey: new Uint8Array(kept.key ?? []).buffer },
          // The browser keys of RFC 8291's example: valid, and never used to send anything here.
          toJSON: () => ({
            endpoint: kept.endpoint,
            keys: {
              p256dh: "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
              auth: "BTBZMqHH6r4Tts7J_aSIgg",
            },
          }),
          unsubscribe: async () => {
            write({ permission: read().permission });
            return true;
          },
        };
    const pushManager = {
      getSubscription: async () => subscription(read()),
      subscribe: async (options: { applicationServerKey: Uint8Array }) => {
        if (read().permission !== "granted") throw new DOMException("Notifications are not allowed", "NotAllowedError");
        const kept: Kept = {
          permission: "granted",
          endpoint: `https://web.push.apple.com/e2e-${crypto.randomUUID()}`,
          key: [...options.applicationServerKey],
        };
        write(kept);
        return subscription(kept);
      },
    };
    const registration = { pushManager, scope: `${location.origin}/fitling/` };
    Object.defineProperty(navigator, "serviceWorker", {
      configurable: true,
      value: {
        ready: Promise.resolve(registration),
        register: async () => registration,
        getRegistration: async () => registration,
        controller: null,
      },
    });
    Object.defineProperty(window, "PushManager", { configurable: true, value: function PushManager() {} });
    Object.defineProperty(window, "Notification", {
      configurable: true,
      value: {
        get permission() {
          return read().permission;
        },
        // The question the browser asks once: yes, or no when the test says so.
        requestPermission: async () => {
          const kept = read();
          if (kept.permission === "default") write({ ...kept, permission: fake.refuse ? "denied" : "granted" });
          return read().permission;
        },
      },
    });
  }, fake);
}
