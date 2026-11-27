import { useCallback, useEffect, useRef, useState } from "react";
import type { FitlingCore, PartnerDays, PartnerEvent, PartnerSnapshot, ReminderSettings } from "../core/fitlingCore";
import { useCore } from "../core/useCore";
import { type Advance, loadPartner, partnerWeek, savePartner, type Partner as StoredPartner } from "../data/creature";
import { noNetwork } from "../data/offline";
import { loadProfile, loadTargetPeriods } from "../data/profileStore";
import { loadReminderSettings, notificationsRefused, planReminders, pushSupport, saveReminderSettings, turnOn } from "../data/push";
import type { Tone } from "../data/saveCreature";
import { supabase } from "../data/supabase";
import { today } from "../day";
import { t } from "../i18n";
import { cleanedName } from "../partner/name";
import { PartnerCanvas } from "../partner/PartnerCanvas";
import { Alert } from "../ui/Alert";
import { ColorSwatches } from "../ui/ColorSwatches";
import { LevelRibbon } from "../ui/LevelRibbon";
import { List, ListRow, ListSection } from "../ui/List";
import { NamePlate } from "../ui/NamePlate";
import { CheckCircleFill, Circle, LockFill } from "../ui/Symbols";
import { PartnerEdit } from "./PartnerEdit";

interface Shown {
  partner: StoredPartner;
  snapshot: PartnerSnapshot;
  /** What the snapshot was made from; the reminders are planned from the same. */
  days: PartnerDays;
}

/** The four ways a day earns XP, in the order of the iPhone, with the part of today's XP each one shows. */
const earnings = [
  { key: "logging", part: "logging" },
  { key: "target", part: "withinTarget" },
  { key: "protein", part: "protein" },
  { key: "workout", part: "workout" },
] as const;

async function load(core: FitlingCore, userID: string, advance: Advance): Promise<Shown | undefined> {
  const now = today();
  const [partner, profile, periods, week] = await Promise.all([
    // A fold the server refuses leaves the partner as it was stored; the next visit folds again (Day.load).
    advance(core).catch(() => loadPartner(supabase, userID)),
    loadProfile(supabase, userID),
    loadTargetPeriods(supabase),
    partnerWeek(supabase, now),
  ]);
  if (!partner) return undefined;
  const days = { creature: partner.state, ...week, periods, fallback: profile.targets, today: now };
  return { partner, snapshot: core.partnerSnapshot(days), days };
}

/** "12:30" for 750 minutes after midnight, as a time field writes it. */
function timeText(minutes: number): string {
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
}

function newsLine(event: PartnerEvent): string {
  switch (event.kind) {
    case "leveledUp":
      return t("partner.news.level %lld", event.level ?? 0);
    case "unlockedItem":
      return t("partner.news.item %@", t(`partner.item.${event.item}`));
    case "unlockedColor":
      return t("partner.news.color");
    case "recoveryBonus":
      return t("partner.news.recovery %lld", event.xp ?? 0);
  }
}

/**
 * The partner tab: how the partner is doing, what today earns, what it wears and its colour (PartnerTabView.swift).
 * Finished days are folded in when it opens and when the app comes back; what that brought shows as news once.
 * Reminders go with Web Push, when this build has the key for it (push.ts); planned again when the tab opens and when
 * the name or the times change.
 */
export function Partner({
  userID,
  advance,
  news,
  onNewsSeen,
}: {
  userID: string;
  advance: Advance;
  news: PartnerEvent[];
  onNewsSeen: () => void;
}) {
  const core = useCore();
  const [shown, setShown] = useState<Shown>();
  const [editing, setEditing] = useState(false);
  const [failed, setFailed] = useState<string>();
  const [reminders, setReminders] = useState<ReminderSettings>(loadReminderSettings);
  const [refused, setRefused] = useState(notificationsRefused);
  const request = useRef(0);
  const saving = useRef<Promise<void>>(Promise.resolve());
  const support = pushSupport();

  const reload = useCallback(async () => {
    if (!core) return;
    // A change still being stored would otherwise be read back as it was (UNFORGET S41); also one made while waiting.
    let waited: Promise<void>;
    do {
      waited = saving.current;
      await waited;
    } while (waited !== saving.current);
    const mine = ++request.current;
    try {
      const next = await load(core, userID, advance);
      if (mine === request.current) setShown(next);
      if (next) void planReminders(supabase, core, { settings: loadReminderSettings(), name: next.partner.name, days: next.days }).catch(() => undefined);
    } catch (error) {
      if (mine === request.current) setFailed(error instanceof Error ? error.message : "error.server");
    }
  }, [core, userID, advance]);

  useEffect(() => {
    void reload();
    const again = () => document.visibilityState === "visible" && void reload();
    document.addEventListener("visibilitychange", again);
    return () => document.removeEventListener("visibilitychange", again);
  }, [reload]);

  /**
   * Shows the change at once and stores it; when storing fails, says so and shows what is stored. Changes are stored
   * one after the other, so a quick crown-then-cap cannot reach the server as cap-then-crown.
   */
  async function change(next: Shown, stored: Parameters<typeof savePartner>[2]) {
    request.current++;
    setShown(next);
    const save = saving.current.then(() => savePartner(supabase, userID, stored, new Date()));
    saving.current = save.catch(() => undefined);
    try {
      await save;
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
      await reload();
    }
  }

  if (!shown || !core) {
    return (
      <div className="tab-page" data-page="partner">
        <div className="toolbar" />
        <h1 className="large-title">{t("partner.title")}</h1>
        <div className="loading tab-loading" aria-busy="true">
          <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
        </div>
        {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
      </div>
    );
  }

  const { partner, snapshot, days } = shown;
  const species = partner.species;
  const rules = core.reminderRules();

  /** Plans for the server; a failure is shown only when the user just changed something. */
  function plan(settings: ReminderSettings, name: string, said: boolean) {
    if (!core) return;
    void planReminders(supabase, core, { settings, name, days }).catch((error: unknown) => {
      if (said) setFailed(error instanceof Error ? error.message : "error.server");
    });
  }

  /** Turning them on asks the browser first; when it says no, they stay off (PartnerViewModel.setRemindersOn). */
  async function setRemindersOn(isOn: boolean) {
    setRefused(false);
    if (isOn) {
      const answer = await turnOn();
      if (answer === "refused") setRefused(true);
      if (answer === "failed") setFailed(noNetwork() ? "error.network" : "error.server");
      if (answer !== "on") return;
    }
    const next = { ...reminders, isOn };
    setReminders(next);
    saveReminderSettings(next);
    plan(next, partner.name, true);
  }

  /** Only a time outside the quiet hours is kept (PartnerViewModel.setReminderTime). */
  function setReminderTime(index: number, text: string) {
    const [hours, minutes] = text.split(":").map(Number);
    const value = hours * 60 + minutes;
    if (!Number.isInteger(value) || value < rules.quietUntil || value >= rules.quietFrom) return;
    const next = { ...reminders, times: reminders.times.map((time, at) => (at === index ? value : time)) };
    setReminders(next);
    saveReminderSettings(next);
    plan(next, partner.name, true);
  }

  function toggle(item: string) {
    if (!core || !snapshot.unlockedItems.includes(item)) return;
    const { worn } = core.wearing({ worn: partner.items, item, unlocked: snapshot.unlockedItems });
    void change({ partner: { ...partner, items: worn }, snapshot, days }, { items: worn });
  }

  function setColor(index: number) {
    if (index < 0 || index >= snapshot.unlockedColorCount || index === partner.state.colorIndex) return;
    void change(
      { partner: { ...partner, state: { ...partner.state, colorIndex: index } }, snapshot: { ...snapshot, colorIndex: index }, days },
      { colorIndex: index },
    );
  }

  function edit(name: string, tone: Tone) {
    setEditing(false);
    const cleaned = cleanedName(name);
    const stored: Parameters<typeof savePartner>[2] = {};
    if (cleaned !== "" && cleaned !== partner.name) stored.name = cleaned;
    if (tone !== partner.state.tone) stored.tone = tone;
    if (Object.keys(stored).length === 0) return;
    const next = { partner: { ...partner, name: stored.name ?? partner.name, state: { ...partner.state, tone } }, snapshot, days };
    void change(next, stored);
    // The reminders carry the name and speak in the voice: planned again with both (PartnerViewModel.rename, setTone).
    if (core) {
      void planReminders(supabase, core, {
        settings: reminders,
        name: next.partner.name,
        days: { ...days, creature: next.partner.state },
      }).catch(() => undefined);
    }
  }

  const remindersFooter =
    support === "homeScreen"
      ? t("partner.reminders.homeScreen")
      : refused
        ? t("partner.reminders.refused")
        : t("partner.reminders.footer %@", partner.name);

  return (
    <div className="tab-page" data-page="partner">
      <div className="toolbar">
        <button type="button" className="nav-back nav-action" onClick={() => setEditing(true)}>
          {t("partner.edit")}
        </button>
      </div>
      <h1 className="large-title">{t("partner.title")}</h1>
      <List>
        <ListSection
          lead={
            // The species tint is light in both modes, so the lettering on it is the dark ribbon ink.
            <div className="partner-hero" data-testid="partner.hero" style={{ backgroundColor: `var(--partner-tint-${species})` }}>
              <div className="partner-hero-figure">
                <PartnerCanvas
                  species={species}
                  look={{
                    colorIndex: snapshot.colorIndex,
                    mood: snapshot.mood,
                    growthStage: snapshot.growthStage,
                    bodyShape: snapshot.bodyShape,
                    trainedRecently: snapshot.trainedRecently,
                    items: partner.items,
                  }}
                  energy={snapshot.energy}
                />
              </div>
              <NamePlate text={partner.name} ribbon={`var(--partner-ribbon-${species})`} />
              <p className="partner-mood">{t(`partner.mood.${snapshot.mood} %@`, partner.name)}</p>
              <LevelRibbon level={snapshot.level} xpIntoLevel={snapshot.xpIntoLevel} xpForNextLevel={snapshot.xpForNextLevel} />
            </div>
          }
        />
        <ListSection header={t("partner.today.title")} footer={t("partner.today.footer")}>
          {earnings.map(({ key, part }) => {
            const earned = snapshot.todayXP[part];
            return (
              <div key={key} className={earned > 0 ? "list-row xp-row" : "list-row xp-row xp-row-open"} data-testid={`partner.today.${key}`}>
                {earned > 0 ? <CheckCircleFill /> : <Circle />}
                <span className="xp-row-title">{t(`partner.today.${key}`)}</span>
                {earned > 0 && <span className="xp-row-earned">{t("partner.xp.earned %lld", earned)}</span>}
              </div>
            );
          })}
        </ListSection>
        <ListSection header={t("partner.items.title")}>
          {snapshot.items.map(({ item, unlockLevel }) =>
            snapshot.unlockedItems.includes(item) ? (
              <ListRow key={item}>
                <label className="toggle-row">
                  <span>{t(`partner.item.${item}`)}</span>
                  <input
                    type="checkbox"
                    role="switch"
                    className="switch"
                    data-testid={`partner.item.${item}`}
                    checked={partner.items.includes(item)}
                    onChange={() => toggle(item)}
                  />
                </label>
              </ListRow>
            ) : (
              <div key={item} className="list-row locked-row" data-testid={`partner.item.${item}`}>
                <span>{t(`partner.item.${item}`)}</span>
                <span className="locked-label">
                  <LockFill size={18} />
                  {t("partner.locked %lld", unlockLevel)}
                </span>
              </div>
            ),
          )}
        </ListSection>
        <ListSection header={t("partner.color.title")}>
          <ListRow>
            <ColorSwatches
              species={species}
              count={snapshot.unlockedColorCount}
              selection={partner.state.colorIndex}
              onSelect={setColor}
              unlockLevels={snapshot.lockedColorLevels}
              label={t("partner.color.title")}
            />
          </ListRow>
        </ListSection>
        {support !== "off" && (
          <ListSection header={t("partner.reminders.title")} footer={remindersFooter}>
            <ListRow>
              <label className="toggle-row">
                <span>{t("partner.reminders.toggle")}</span>
                <input
                  type="checkbox"
                  role="switch"
                  className="switch"
                  data-testid="partner.reminders.toggle"
                  checked={support === "ready" && reminders.isOn}
                  disabled={support !== "ready"}
                  onChange={(event) => void setRemindersOn(event.target.checked)}
                />
              </label>
            </ListRow>
            {support === "ready" &&
              reminders.isOn &&
              reminders.times.map((time, index) => (
                <ListRow key={index}>
                  <label className="labeled picker-row">
                    <span>{t(index === 0 ? "partner.reminders.first" : "partner.reminders.second")}</span>
                    <input
                      className="picker"
                      type="time"
                      step={60}
                      min={timeText(rules.quietUntil)}
                      max={timeText(rules.quietFrom - 1)}
                      value={timeText(time)}
                      data-testid={`partner.reminders.time.${index}`}
                      onChange={(event) => setReminderTime(index, event.target.value)}
                    />
                  </label>
                </ListRow>
              ))}
          </ListSection>
        )}
      </List>
      {editing && <PartnerEdit name={partner.name} tone={partner.state.tone as Tone} onSave={edit} onCancel={() => setEditing(false)} />}
      {news.length > 0 && !editing && <Alert title={t("partner.news.title")} message={news.map(newsLine).join("\n")} onClose={onNewsSeen} />}
      {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
    </div>
  );
}
