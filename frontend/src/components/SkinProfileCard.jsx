import { Panel } from "./ui/Panel.jsx";
import { CheckboxTag, LABEL, Select } from "./ui/Field.jsx";
import { CONCERNS, SKIN_TYPES } from "../lib/constants.js";

export function SkinProfileCard({ skinType, concerns, onSkinTypeChange, onToggleConcern }) {
  return (
    <Panel
      number="01"
      eyebrow="Profile"
      title="Skin profile"
      description="Used to escalate severity for reactive skin types and conditions. Rosacea and eczema raise every conflict to high."
    >
      <div className="grid grid-cols-1 gap-8 md:grid-cols-[minmax(0,1fr)_minmax(0,2fr)] md:gap-12">
        <Select
          label="Skin type"
          value={skinType}
          options={SKIN_TYPES}
          onChange={(event) => onSkinTypeChange(event.target.value)}
        />

        <fieldset className="flex min-w-0 flex-col gap-3 border-0 p-0">
          <legend className={`${LABEL} mb-3 flex w-full items-baseline justify-between gap-4`}>
            Concerns
            <span className="font-medium normal-case tracking-normal text-black/60">
              {concerns.length ? `${concerns.length} selected` : "Optional"}
            </span>
          </legend>
          <div className="flex flex-wrap gap-2">
            {CONCERNS.map((concern) => (
              <CheckboxTag
                key={concern.value}
                name="concerns"
                checked={concerns.includes(concern.value)}
                onChange={() => onToggleConcern(concern.value)}
              >
                {concern.label}
              </CheckboxTag>
            ))}
          </div>
        </fieldset>
      </div>
    </Panel>
  );
}
