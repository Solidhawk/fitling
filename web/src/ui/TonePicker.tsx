import type { Tone } from "../data/saveCreature";
import { t } from "../i18n";

export const tones: Tone[] = ["sweet", "funny", "coach"];

/** The voice of the reminders, each with one reminder in that voice, so the choice is heard rather than described. */
export function TonePicker({ tone, onChange, label }: { tone: Tone; onChange: (tone: Tone) => void; label: string }) {
  return (
    <div role="radiogroup" aria-label={label}>
      {tones.map((value) => (
        <button
          key={value}
          type="button"
          role="radio"
          aria-checked={tone === value}
          className="list-row list-row-button choice"
          onClick={() => onChange(value)}
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
  );
}
