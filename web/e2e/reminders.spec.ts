import { expect, type Page, test } from "./fixtures";
import { admin, createUser, nl, signIn } from "./users";

// The partner's reminders on the web (phase 7), as ReminderTests on iOS: turned on from the partner tab, planned with
// the rules of the app and handed to the server, which sends them with Web Push. Playwright has no push service, so
// the browser's is faked: the subscription, the permission, and a browser without push (Safari outside the home
// screen). The build has the public test key of the CI job (VITE_VAPID_PUBLIC_KEY).

test.use({ timezoneId: "Europe/Amsterdam" });

type Fake = { refuse?: boolean; noPush?: boolean };

/**
 * A push service in the page. What the browser would keep, the permission and the subscription, survives a reload
 * (sessionStorage), as it does in a real browser.
 */
async function fakePush(page: Page, fake: Fake = {}) {
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
        if (fake.refuse) {
          write({ permission: "denied" });
          throw new DOMException("Notifications are not allowed", "NotAllowedError");
        }
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
        requestPermission: async () => read().permission,
      },
    });
  }, fake);
}

async function openPartner(page: Page) {
  const user = await createUser({ profile: true, creature: true });
  await signIn(page, user.email);
  await expect(page.getByTestId("day.progress")).toBeVisible({ timeout: 15_000 });
  await page.getByRole("tab", { name: nl("partner.title") }).click();
  await expect(page.getByTestId("partner.hero")).toBeVisible({ timeout: 15_000 });
  return user;
}

async function planned(userID: string) {
  const { data, error } = await admin.from("push_reminders").select("fire_at, title, body").eq("user_id", userID).order("fire_at");
  if (error) throw error;
  return data;
}

/** Minutes after midnight in Amsterdam, where the browser of these tests is. */
function minutes(moment: string): number {
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Amsterdam", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
    .formatToParts(new Date(moment))
    .reduce<Record<string, string>>((all, part) => ({ ...all, [part.type]: part.value }), {});
  return Number(parts.hour) * 60 + Number(parts.minute);
}

/** What an owl with the sweet voice can say (CreatureEngine.messageKeys), in Dutch. */
const sweetMessages = ["fit", "normal", "tooMuch", "tooLittle", "asleep", "hungry"].flatMap((topic) =>
  [1, 2, 3].map((variant) => nl(`creature.message.${topic}.sweet.${variant}`)),
);

test("remindersAreHandedToTheServer", async ({ page }, info) => {
  await fakePush(page);
  const user = await openPartner(page);
  await page.getByTestId("partner.reminders.toggle").scrollIntoViewIfNeeded();
  await page.screenshot({ path: `test-results/screens/${info.project.name}-herinneringen.png` });
  await page.getByTestId("partner.reminders.toggle").click();
  await expect(page.getByTestId("partner.reminders.toggle")).toBeChecked();
  // Today what is still to come, tomorrow both: lunch and dinner, with the partner's name and what it would say.
  await expect.poll(async () => (await planned(user.id)).length, { timeout: 15_000 }).toBeGreaterThanOrEqual(2);
  for (const reminder of await planned(user.id)) {
    expect([12 * 60 + 30, 18 * 60 + 30]).toContain(minutes(reminder.fire_at));
    expect(reminder.title).toBe("Uiltje");
    expect(sweetMessages).toContain(reminder.body);
    expect(Date.parse(reminder.fire_at)).toBeGreaterThan(Date.now());
  }
  await page.screenshot({ path: `test-results/screens/${info.project.name}-herinneringen-aan.png` });

  // Another time is planned again; the settings stay in this browser.
  await page.getByTestId("partner.reminders.time.1").fill("19:00");
  await expect.poll(async () => (await planned(user.id)).map((reminder) => minutes(reminder.fire_at))).toContain(19 * 60);
  await page.reload();
  await page.getByRole("tab", { name: nl("partner.title") }).click();
  await expect(page.getByTestId("partner.reminders.time.1")).toHaveValue("19:00", { timeout: 15_000 });

  // A time in the quiet hours is not taken (ReminderSettings.isAllowed).
  await page.getByTestId("partner.reminders.time.0").fill("22:00");
  await expect(page.getByTestId("partner.reminders.time.0")).toHaveValue("12:30");

  await page.getByTestId("partner.reminders.toggle").click();
  await expect(page.getByTestId("partner.reminders.toggle")).not.toBeChecked();
  await expect.poll(async () => (await planned(user.id)).length).toBe(0);
});

test("refusedNotificationsKeepRemindersOff", async ({ page }) => {
  await fakePush(page, { refuse: true });
  const user = await openPartner(page);
  await page.getByTestId("partner.reminders.toggle").click();
  await expect(page.getByText(nl("partner.reminders.refused"))).toBeVisible();
  await expect(page.getByTestId("partner.reminders.toggle")).not.toBeChecked();
  const { data } = await admin.from("push_subscriptions").select("id").eq("user_id", user.id);
  expect(data).toEqual([]);
});

test("withoutTheHomeScreenRemindersSayHow", async ({ page }) => {
  await fakePush(page, { noPush: true });
  await openPartner(page);
  await expect(page.getByText(nl("partner.reminders.homeScreen"))).toBeVisible();
  await expect(page.getByTestId("partner.reminders.toggle")).toBeDisabled();
});

// RootViewModel on iOS empties the reminders at sign-out: they carry the partner's name and mood.
test("signingOutRemovesTheReminders", async ({ page }) => {
  await fakePush(page);
  const user = await openPartner(page);
  await page.getByTestId("partner.reminders.toggle").click();
  await expect.poll(async () => (await planned(user.id)).length, { timeout: 15_000 }).toBeGreaterThanOrEqual(2);
  await page.getByRole("tab", { name: nl("profile.title") }).click();
  await page.getByRole("button", { name: nl("account.title") }).click();
  await page.getByRole("button", { name: nl("account.signOut") }).click();
  await expect(page.locator('[data-screen="welcome"]')).toBeAttached();
  const { data } = await admin.from("push_subscriptions").select("id").eq("user_id", user.id);
  expect(data).toEqual([]);
  expect(await planned(user.id)).toEqual([]);
});
