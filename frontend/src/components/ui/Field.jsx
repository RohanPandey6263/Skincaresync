import { useId } from "react";
import { Icon } from "./Icon.jsx";

export function useFieldIds(providedId) {
  const generated = useId();
  const id = providedId ?? generated;
  return { id, hintId: `${id}-hint`, errorId: `${id}-error` };
}

export function FieldShell({ id, hintId, errorId, label, hint, error, children, className = "" }) {
  return (
    <div className={`field${error ? " field--invalid" : ""} ${className}`.trim()}>
      {label ? (
        <label className="field__label" htmlFor={id}>
          {label}
        </label>
      ) : null}
      {children}
      {hint && !error ? (
        <p className="field__hint" id={hintId}>
          {hint}
        </p>
      ) : null}
      {error ? (
        <p className="field__error" id={errorId}>
          <Icon name="alertTriangle" size={13} />
          {error}
        </p>
      ) : null}
    </div>
  );
}

export function TextInput({ id: providedId, label, hint, error, className = "", ...rest }) {
  const { id, hintId, errorId } = useFieldIds(providedId);

  return (
    <FieldShell
      id={id}
      hintId={hintId}
      errorId={errorId}
      label={label}
      hint={hint}
      error={error}
      className={className}
    >
      <input
        id={id}
        className="input"
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? errorId : hint ? hintId : undefined}
        {...rest}
      />
    </FieldShell>
  );
}

export function Select({
  id: providedId,
  label,
  hint,
  error,
  options,
  className = "",
  ...rest
}) {
  const { id, hintId, errorId } = useFieldIds(providedId);

  return (
    <FieldShell
      id={id}
      hintId={hintId}
      errorId={errorId}
      label={label}
      hint={hint}
      error={error}
      className={className}
    >
      <div className="selectWrap">
        <select
          id={id}
          className="input select"
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? errorId : hint ? hintId : undefined}
          {...rest}
        >
          {options.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
        <Icon name="chevronDown" size={15} className="selectWrap__icon" />
      </div>
    </FieldShell>
  );
}

export function CheckboxTag({ checked, onChange, children, name }) {
  return (
    <label className={`checkTag${checked ? " is-checked" : ""}`}>
      <input type="checkbox" name={name} checked={checked} onChange={onChange} />
      <span className="checkTag__box" aria-hidden="true">
        <Icon name="checkCircle" size={12} strokeWidth={2.5} />
      </span>
      <span className="checkTag__label">{children}</span>
    </label>
  );
}
