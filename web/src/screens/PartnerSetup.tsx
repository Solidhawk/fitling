import { useState } from "react";
import { useCore } from "../core/useCore";
import { saveCreature, type Tone } from "../data/saveCreature";
import { today } from "../day";
import { supabase } from "../data/supabase";
import { t } from "../i18n";
import { cleanedName, limitedName } from "../partner/name";
import { PartnerCanvas } from "../partner/PartnerCanvas";
import { type Species, species as allSpecies } from "../partner/species";
import { Alert } from "../ui/Alert";
import { ColorSwatches } from "../ui/ColorSwatches";
import { PrimaryButton } from "../ui/Buttons";
import { FittedText } from "../ui/FittedText";
import { List, ListRow, ListSection } from "../ui/List";
import { NamePlate } from "../ui/NamePlate";
import { NavBar } from "../ui/NavBar";
import { TonePicker } from "../ui/TonePicker";

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
        {/* The tiles on the ground itself, without a white row behind them (listRowBackground(.clear)). */}
        <ListSection
          header={<span className="setup-intro">{t("partner.setup.intro")}</span>}
          lead={
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
                    twoLinesWhenLarge
                    style={{ backgroundColor: `var(--partner-ribbon-${species})` }}
                  />
                </button>
              ))}
            </div>
          }
        />
        {chosen && (
          <>
            <ListSection
              lead={
                // How the partner starts: small, at the first growth stage, happy to meet the user.
                <div className="partner-preview" aria-hidden="true" style={{ backgroundColor: `var(--partner-tint-${chosen})` }}>
                  <div className="partner-preview-figure">
                    <PartnerCanvas species={chosen} look={{ colorIndex, mood: "happy", growthStage: 0 }} energy={0.8} />
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
                <ColorSwatches species={chosen} count={colorCount} selection={colorIndex} onSelect={setColorIndex} label={t("partner.setup.color")} />
              </ListRow>
            </ListSection>
            <ListSection header={t("partner.setup.tone")} footer={t("partner.setup.tone.footer")}>
              <TonePicker tone={tone} onChange={setTone} label={t("partner.setup.tone")} />
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
