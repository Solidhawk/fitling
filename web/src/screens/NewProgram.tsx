import { useState } from "react";
import { t } from "../i18n";
import { FormSheet } from "../ui/FormSheet";
import { ListRow, ListSection } from "../ui/List";
import { Stepper } from "../ui/Stepper";

/** A name and the number of training days for a new programme of the user's own (NewProgramSheet on iOS). */
export function NewProgram({ onCreate, onCancel }: { onCreate: (name: string, days: number) => void; onCancel: () => void }) {
  const [name, setName] = useState("");
  const [days, setDays] = useState(3);
  return (
    <FormSheet
      title={t("training.program.new")}
      saveLabel={t("common.save")}
      canSave={name.trim() !== ""}
      onSave={() => onCreate(name.trim(), days)}
      onCancel={onCancel}
    >
      <ListSection>
        <ListRow>
          <input
            className="text-field"
            aria-label={t("training.program.name")}
            placeholder={t("training.program.name")}
            data-testid="training.program.name"
            value={name}
            onChange={(event) => setName(event.target.value)}
          />
        </ListRow>
        <ListRow>
          <Stepper label={t("training.program.days %lld", days)} value={days} min={1} max={7} onChange={setDays} testID="training.program.days" />
        </ListRow>
      </ListSection>
    </FormSheet>
  );
}
