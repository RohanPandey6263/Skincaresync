import { useId } from "react";
import { Icon } from "./Icon.jsx";

export function useFieldIds(providedId) {
  const generated = useId();
  const id = providedId ?? generated;
  return { id, hintId: `${id}-hint`, errorId: `${id}-error` };
}

/**
 * Inputs are pills of pale linen with no visible resting border — the system
 * asks for a soft field rather than a boxed one. Focus is a sage border plus a
 * ring, never a browser default blue.
 *
 * The ring is on `:focus-visible` for the field itself but the error state
 * shows a terracotta border at all times: an invalid field has to be findable
 * without tabbing to it, and colour alone does not carry it — the message
 * below states the problem in words.
 */
const CONTROL =
  "h-11 w-full rounded-full border border-transparent bg-linen px-5 font-sans text-md text-forest " +
  "placeholder:text-muted transition-[border-color,box-shadow,background-color] duration-300 " +
  "hover:bg-clay/40 focus:outline-none focus:border-sage focus:bg-white " +
  "focus-visible:ring-2 focus-visible:ring-sage/40 " +
  "disabled:cursor-not-allowed disabled:opacity-50 " +
  "aria-invalid:border-terracotta aria-invalid:bg-terracotta-100/40";

export function FieldShell({ id, hintId, errorId, label, hint, error, children, className = "" }) {
  return (
    <div className={`flex flex-col gap-2 ${className}`.trim()}>
      {label ? (
        <label
          className="font-sans text-2xs uppercase tracking-label text-muted"
          htmlFor={id}
        >
          {label}
        </label>
      ) : null}
      {children}
      {hint && !error ? (
        <p className="font-sans text-sm text-muted" id={hintId}>
          {hint}
        </p>
      ) : null}
      {error ? (
        <p
          className="inline-flex items-center gap-2 font-sans text-sm text-terracotta-700"
          id={errorId}
        >
          <Icon name="alertTriangle" size={13} strokeWidth={1.75} className="shrink-0" />
          {error}
        </p>
      ) : null}
    </div>
  );
}

export function TextInput({ id: providedId, label, hint, error, className = "", ...rest }) {
  const { id, hintId, errorId } = useFieldIds(providedId);

  return (
    <FieldShell id={id} hintId={hintId} errorId={errorId} label={label} hint={hint} error={error} className={className}>
      <input
        id={id}
        className={CONTROL}
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? errorId : hint ? hintId : undefined}
        {...rest}
      />
    </FieldShell>
  );
}

export function Select({ id: providedId, label, hint, error, options, className = "", ...rest }) {
  const { id, hintId, errorId } = useFieldIds(providedId);

  return (
    <FieldShell id={id} hintId={hintId} errorId={errorId} label={label} hint={hint} error={error} className={className}>
      <div className="relative">
        <select
          id={id}
          className={`${CONTROL} cursor-pointer appearance-none pr-12`}
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
        <Icon
          name="chevronDown"
          size={15}
          strokeWidth={1.5}
          className="pointer-events-none absolute right-5 top-1/2 -translate-y-1/2 text-muted"
        />
      </div>
    </FieldShell>
  );
}

/**
 * A checkbox styled as a selectable pill. The native input stays in the DOM —
 * visually hidden but focusable — so keyboard, screen readers and form
 * semantics all keep working; only its rendering is replaced.
 */
export function CheckboxTag({ checked, onChange, children, name }) {
  return (
    <label
      className={`group inline-flex h-11 cursor-pointer items-center gap-2.5 rounded-full border px-5
                  font-sans text-sm transition-[background-color,border-color,color] duration-300
                  has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-sage
                  has-[:focus-visible]:ring-offset-2 has-[:focus-visible]:ring-offset-alabaster
                  ${
                    checked
                      ? "border-forest bg-forest text-alabaster"
                      : "border-stone bg-white text-subtle hover:border-sage hover:bg-sage-100/50"
                  }`}
    >
      <input
        className="sr-only"
        type="checkbox"
        name={name}
        checked={checked}
        onChange={onChange}
      />
      <span
        className={`grid h-4 w-4 place-items-center rounded-full border transition-colors duration-300 ${
          checked ? "border-alabaster bg-alabaster text-forest" : "border-clay bg-transparent text-transparent"
        }`}
        aria-hidden="true"
      >
        <Icon name="checkCircle" size={12} strokeWidth={2.5} />
      </span>
      {children}
    </label>
  );
}
