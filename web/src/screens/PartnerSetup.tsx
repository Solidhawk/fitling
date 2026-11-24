import { useState } from "react";
import { useCore } from "../core/useCore";
import { saveCreature, type Tone } from "../data/saveCreature";
import { supabase } from "../data/supabase";
import { t } from "../i18n";
import { hue } from "../partner/framing";
import { cleanedName, limitedName } from "../partner/name";
import { PartnerCanvas } from "../partner/PartnerCanvas";
import { type Species, species as allSpecies } from "../partner/species";
import { Alert } from "../ui/Alert";
import { PrimaryButton } from "../ui/Buttons";
import { FittedText } from "../ui/FittedText";
import { List, ListRow, ListSection } from "../ui/List";
import { NamePlate } from "../ui/NamePlate";
import { NavBar } from "../ui/NavBar";

const tones: Tone[] = ["sweet", "funny", "coach"];

/** Today where the user is, as "2026-11-24". */
function today(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

/**
 * Choosing a partner: species, name, colour and the voice of its reminders (PartnerSetupView.swift and
 * PartnerSetupViewModel.swift). The species' name is filled in until the user types one.
 */
export function PartnerSetup({ userID, onFinished }: { userID: string; onFinished: () => void }) {
  const core = useCore();
  const [chosen, setChosen] = useState<Species>();
  const [name, setName] = useState("");
  const [suggested, setSuggested] = useState<string>();
  const [colorIndex, setColorIndex] = useState(0);
  const [tone, setTone] = useState<Tone>("sweet");
  const [saving, setSaving] = useState(false);
  const [saveFailed, setSaveFailed] = useState(false);
  const start = core?.creature({ level: 1 });
  const colorCount = start?.colorCount ?? 0;
  const canSave = chosen !== undefined && cleanedName(name) !== "" && start !== undefined && !saving;

  function choose(species: Species) {
    setChosen(species);
    const speciesName = t(`creature.${species}.name`);
    if (name === "" || name === suggested) {
      setName(speciesName);
      setSuggested(speciesName);
    }
  }

  async function save() {
    if (!canSave || !chosen || !start) return;
    setSaving(true);
    try {
      await saveCreature(supabase, {
        userID,
        species: chosen,
        name: cleanedName(name),
        colorIndex: Math.min(Math.max(colorIndex, 0), colorCount - 1),
        tone,
        startShape: start.startShape,
        today: today(),
        now: new Date(),
      });
      onFinished();
    } catch {
      setSaveFailed(true);
    } finally {
      setSaving(false);
    }
  }

  return (
    <main className="screen with-bottom-bar" data-screen="partnerSetup">
      <NavBar title={t("partner.setup.title")} />
      <List>
        <ListSection header={<span className="setup-intro">{t("partner.setup.intro")}</span>}>
          <div className="species-grid">
            {allSpecies.map((species) => (
              <button
                key={species}
                type="button"
                className="species-tile"
                aria-pressed={chosen === species}
                aria-label={t(`creature.${species}.name`)}
                aria-description={t(`creature.${species}.note`)}
                data-testid={`partner.setup.species.${species}`}
                style={{ backgroundColor: `var(--partner-tint-${species})` }}
                onClick={() => choose(species)}
              >
                <PartnerCanvas species={species} />
                <FittedText
                  className="species-name"
                  text={t(`creature.${species}.name`)}
                  minimumScale={0.75}
                  style={{ backgroundColor: `var(--partner-ribbon-${species})` }}
                />
              </button>
            ))}
          </div>
        </ListSection>
        {chosen && (
          <>
            <ListSection
              lead={
                // How the partner starts: small, at the first growth stage, happy to meet the user.
                <div className="partner-preview" aria-hidden="true" style={{ backgroundColor: `var(--partner-tint-${chosen})` }}>
                  <div className="partner-preview-figure">
                    <PartnerCanvas species={chosen} look={{ colorIndex, mood: "happy", growthStage: 0 }} />
                  </div>
                  <NamePlate text={cleanedName(name) || t(`creature.${chosen}.name`)} ribbon={`var(--partner-ribbon-${chosen})`} />
                </div>
              }
              footer={t("partner.setup.name.footer")}
            >
              <ListRow>
                <input
                  className="text-field name-field"
                  autoCapitalize="words"
                  aria-label={t("partner.setup.name")}
                  placeholder={t(`creature.${chosen}.name`)}
                  data-testid="partner.setup.name"
                  value={name}
                  onChange={(event) => setName(limitedName(event.target.value))}
                />
              </ListRow>
            </ListSection>
            <ListSection header={t("partner.setup.color")}>
              <ListRow>
                <span className="swatches" role="radiogroup" aria-label={t("partner.setup.color")}>
                  {Array.from({ length: colorCount }, (_, index) => (
                    <button
                      key={index}
                      type="button"
                      role="radio"
                      aria-checked={colorIndex === index}
                      aria-label={t("partner.color %lld", index + 1)}
                      className="swatch"
                      onClick={() => setColorIndex(index)}
                    >
                      <span
                        className="swatch-fill"
                        style={{ backgroundColor: `var(--partner-ribbon-${chosen})`, filter: `hue-rotate(${hue(index)}deg)` }}
                      />
                    </button>
                  ))}
                </span>
              </ListRow>
            </ListSection>
            <ListSection header={t("partner.setup.tone")} footer={t("partner.setup.tone.footer")}>
              <div role="radiogroup" aria-label={t("partner.setup.tone")}>
                {tones.map((value) => (
                  <button
                    key={value}
                    type="button"
                    role="radio"
                    aria-checked={tone === value}
                    className="list-row list-row-button choice"
                    onClick={() => setTone(value)}
                  >
                    <span className="choice-text">
                      <span>{t(`partner.tone.${value}`)}</span>
                      <span className="choice-detail">{t(`creature.message.hungry.${value}.1`)}</span>
                    </span>
                    {tone === value && (
                      <svg className="checkmark" viewBox="0 0 14 12" aria-hidden="true">
                        <path d="M1 6.5l4 4L13 1" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
                      </svg>
                    )}
                  </button>
                ))}
              </div>
            </ListSection>
          </>
        )}
      </List>
      <div className="bottom-bar">
        <PrimaryButton disabled={!canSave} onClick={() => void save()} data-testid="partner.setup.done">
          {t("partner.setup.done")}
        </PrimaryButton>
      </div>
      {saveFailed && <Alert title={t("error.server")} onClose={() => setSaveFailed(false)} />}
    </main>
  );
}
