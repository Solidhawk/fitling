import { ArrowUpToLine, CornerDownRight, TriangleAlert } from "lucide-react";
import { type CSSProperties, useCallback, useEffect, useState } from "react";
import type { DailyPlan, FitlingCore, Targets } from "../core/fitlingCore";
import { useCore } from "../core/useCore";
import type { AuthService } from "../data/auth";
import { editedProfile, loadProfile, type Body, type Profile as StoredProfile, saveProfile } from "../data/profileStore";
import { supabase } from "../data/supabase";
import { today } from "../day";
import { decimal, fixed, kcal, percent } from "../format";
import { t } from "../i18n";
import { orderedWarnings, warningKeys } from "../profileTexts";
import { ActionSheet } from "../ui/ActionSheet";
import { Alert } from "../ui/Alert";
import { SecondaryButton } from "../ui/Buttons";
import { List, ListRow, ListSection } from "../ui/List";
import { MacroBlocks } from "../ui/MacroBlocks";
import { Menu } from "../ui/Menu";
import { About, Account, DeleteAccount } from "./Account";
import { EditProfile, EditTargets } from "./EditProfile";

type Page = "profile" | "account" | "about" | "delete";

/**
 * The Dagdoel tab: how the daily target is built, then Account with what lies behind it, each pushed on the one
 * before (ProfileView.swift). Changes go straight to the server.
 */
export function Profile({ userID, auth }: { userID: string; auth: AuthService }) {
  const core = useCore();
  const [profile, setProfile] = useState<StoredProfile>();
  const [loadFailed, setLoadFailed] = useState(false);
  const [page, setPage] = useState<Page>("profile");

  const load = useCallback(async () => {
    setLoadFailed(false);
    try {
      setProfile(await loadProfile(supabase, userID));
    } catch {
      setLoadFailed(true);
    }
  }, [userID]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => window.scrollTo(0, 0), [page]);

  if (page === "account") return <Account auth={auth} onBack={() => setPage("profile")} onOpen={setPage} />;
  if (page === "about") return <About onBack={() => setPage("account")} />;
  if (page === "delete") return <DeleteAccount auth={auth} onBack={() => setPage("account")} />;

  if (loadFailed) {
    return (
      <div className="tab-page unavailable" data-page="profile">
        <h1 className="large-title">{t("profile.title")}</h1>
        <p>{t("error.server")}</p>
        <SecondaryButton onClick={() => void load()}>{t("common.connection.retry")}</SecondaryButton>
      </div>
    );
  }
  if (!core || !profile) {
    return (
      <div className="tab-page loading" data-page="profile" aria-busy="true">
        <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
      </div>
    );
  }
  return <ProfileView core={core} profile={profile} onChange={setProfile} onAccount={() => setPage("account")} />;
}

function ProfileView({
  core,
  profile,
  onChange,
  onAccount,
}: {
  core: FitlingCore;
  profile: StoredProfile;
  onChange: (profile: StoredProfile) => void;
  onAccount: () => void;
}) {
  const [editing, setEditing] = useState<"profile" | "targets">();
  const [askRecalculate, setAskRecalculate] = useState(false);
  const [saveFailed, setSaveFailed] = useState(false);
  const day = today();
  const plan = core.dailyPlan({ ...profile.body, today: day });
  const rules = core.profileRules();
  // Warnings for the target as it is now, also one the user typed in. They never block (D-10).
  const warnings = orderedWarnings(core.warnings({ kcal: profile.targets.kcal, bmr: plan.bmr, tdee: plan.tdee, sex: profile.body.sex }).warnings);

  async function store(next: StoredProfile, newTargets?: Targets) {
    try {
      await saveProfile(supabase, next, { newTargets, today: day, now: new Date() });
      onChange(next);
      return true;
    } catch {
      setSaveFailed(true);
      return false;
    }
  }

  async function saveBody(body: Body) {
    const edit = editedProfile(profile, body, core.dailyPlan({ ...body, today: day }).targets);
    if (!(await store(edit.profile, edit.newTargets))) return;
    setEditing(undefined);
    if (edit.askRecalculate) setAskRecalculate(true);
  }

  async function recalculate(body = profile.body) {
    const planned = core.dailyPlan({ ...body, today: day }).targets;
    if (await store({ ...profile, body, targets: planned, targetsAreManual: false }, planned)) setEditing(undefined);
    setAskRecalculate(false);
  }

  async function saveTargets(targets: Targets) {
    if (await store({ ...profile, targets, targetsAreManual: true }, targets)) setEditing(undefined);
  }

  return (
    <div className="tab-page" data-page="profile">
      <div className="toolbar">
        <Menu
          label={t("profile.adjust")}
          testID="profile.adjust"
          items={[
            { label: t("profile.edit"), onSelect: () => setEditing("profile") },
            { label: t("profile.editTargets"), onSelect: () => setEditing("targets") },
          ]}
        />
      </div>
      <h1 className="large-title">{t("profile.title")}</h1>
      <List>
        <ListSection
          lead={
            <div className="profile-header">
              <TargetBuildUp core={core} plan={plan} profile={profile} activityFactor={rules.activityFactors[profile.body.activityLevel]} />
              {profile.targetsAreManual && <p className="note">{t("profile.targets.manual")}</p>}
              {plan.floorApplied && !profile.targetsAreManual && (
                <p className="note">
                  <ArrowUpToLine aria-hidden="true" size={16} strokeWidth={2.4} />
                  <span>{t("targets.floor")}</span>
                </p>
              )}
              {warnings.map((warning) => (
                <p key={warning} className="note">
                  <TriangleAlert aria-hidden="true" size={16} strokeWidth={2.4} />
                  <span>{t(warningKeys[warning])}</span>
                </p>
              ))}
            </div>
          }
          footer={t("profile.rounding")}
        >
          <ListRow>
            <span className="labeled">
              <span>{t("profile.proteinPerKg")}</span>
              <span className="value" data-testid="profile.proteinPerKg">
                {t("profile.proteinPerKg.value %@", fixed(rules.proteinPerKg[profile.body.goal], 1))}
              </span>
            </span>
          </ListRow>
        </ListSection>
        <ListSection>
          <ListRow onClick={onAccount} chevron>
            {t("account.title")}
          </ListRow>
        </ListSection>
      </List>
      {editing === "profile" && <EditProfile core={core} profile={profile} onSave={(body) => void saveBody(body)} onCancel={() => setEditing(undefined)} />}
      {editing === "targets" && (
        <EditTargets
          targets={profile.targets}
          limits={rules.targetLimits}
          onSave={(targets) => void saveTargets(targets)}
          onRecalculate={() => void recalculate()}
          onCancel={() => setEditing(undefined)}
        />
      )}
      {askRecalculate && (
        <ActionSheet
          title={t("profile.recalculate.title")}
          actions={[{ label: t("profile.recalculate.confirm"), onSelect: () => void recalculate() }]}
          cancelLabel={t("profile.recalculate.keep")}
          onCancel={() => setAskRecalculate(false)}
        />
      )}
      {saveFailed && <Alert title={t("error.server")} onClose={() => setSaveFailed(false)} />}
    </div>
  );
}

/**
 * How the daily target is built, as steps that grow towards it: resting metabolism, times how active you are, times
 * your goal. Every number on the way is shown, then the macros as blocks (TargetBuildUp in ProfileView.swift).
 */
function TargetBuildUp({ core, plan, profile, activityFactor }: { core: FitlingCore; plan: DailyPlan; profile: StoredProfile; activityFactor: number }) {
  const targets = profile.targets;
  const largest = Math.max(plan.bmr, plan.tdee, targets.kcal, 1);
  const goalFactor = core.goalFactors()[profile.body.goal];
  return (
    <div className="card build-up">
      <Step label={t("profile.bmr")} value={plan.bmr} share={plan.bmr / largest} />
      <Factor text={t("profile.buildUp.activity %@", decimal(activityFactor, 3))} />
      <Step label={t("profile.tdee")} value={plan.tdee} share={plan.tdee / largest} />
      <Factor text={t("profile.buildUp.goal %@", percent(goalFactor))} />
      <div className="build-step-width" style={{ "--share": Math.max(targets.kcal / largest, 0.62) } as CSSProperties}>
        <div className="build-target">
          <span className="build-target-label">{t("profile.buildUp.target")}</span>
          <span className="build-target-value" data-testid="profile.target">
            {kcal(targets.kcal)}
          </span>
        </div>
      </div>
      <MacroBlocks targets={targets} shares={core.kcalShares(targets)} />
    </div>
  );
}

/** A step as wide as its share of the largest number, so the steps rise towards the target; full width at large text. */
function Step({ label, value, share }: { label: string; value: number; share: number }) {
  return (
    <div className="build-step-width" style={{ "--share": Math.max(share, 0.5) } as CSSProperties}>
      <div className="build-step">
        <span className="build-step-label">{label}</span>
        <span className="build-step-value">{kcal(Math.round(value))}</span>
      </div>
    </div>
  );
}

function Factor({ text }: { text: string }) {
  return (
    <p className="build-factor">
      <CornerDownRight aria-hidden="true" size={15} strokeWidth={2.4} />
      <span>{text}</span>
    </p>
  );
}
