import { useState } from "react";
import type { Tone } from "../data/saveCreature";
import { t } from "../i18n";
import { cleanedName, limitedName } from "../partner/name";
import { FormSheet } from "../ui/FormSheet";
import { ListRow, ListSection } from "../ui/List";
import { TonePicker } from "../ui/TonePicker";

/** Name and voice, edited in a sheet (PartnerEditView in PartnerTabView.swift). */
export function PartnerEdit({
  name,
  tone,
  onSave,
  onCancel,
}: {
  name: string;
  tone: Tone;
  onSave: (name: string, tone: Tone) => void;
  onCancel: () => void;
}) {
  const [text, setText] = useState(name);
  const [voice, setVoice] = useState(tone);
  return (
    <FormSheet
      title={t("partner.edit")}
      saveLabel={t("common.save")}
      canSave={cleanedName(text) !== ""}
      onSave={() => onSave(text, voice)}
      onCancel={onCancel}
    >
      <ListSection header={t("partner.setup.name")}>
        <ListRow>
          <input
            className="text-field"
            autoCapitalize="words"
            aria-label={t("partner.setup.name")}
            data-testid="partner.edit.name"
            value={text}
            onChange={(event) => setText(limitedName(event.target.value))}
          />
        </ListRow>
      </ListSection>
      <ListSection header={t("partner.setup.tone")}>
        <TonePicker tone={voice} onChange={setVoice} label={t("partner.setup.tone")} />
      </ListSection>
    </FormSheet>
  );
}
