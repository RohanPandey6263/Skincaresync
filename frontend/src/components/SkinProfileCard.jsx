import { Panel } from "./ui/Panel.jsx";
import { CheckboxTag, Select } from "./ui/Field.jsx";
import { CONCERNS, SKIN_TYPES } from "../lib/constants.js";

export function SkinProfileCard({ skinType, concerns, onSkinTypeChange, onToggleConcern }) {
  return (
    <Panel
      title="Skin profile"
      icon="user"
      description="Used to escalate severity for reactive skin types and conditions."
      className="profilePanel"
    >
      <div className="profileGrid">
        <Select
          label="Skin type"
          value={skinType}
          options={SKIN_TYPES}
          onChange={(event) => onSkinTypeChange(event.target.value)}
        />

        <fieldset className="fieldset">
          <legend className="field__label">
            Concerns
            <span className="field__labelMeta">
              {concerns.length ? `${concerns.length} selected` : "Optional"}
            </span>
          </legend>
          <div className="tagGroup">
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
