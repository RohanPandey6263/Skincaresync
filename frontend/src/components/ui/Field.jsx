import { useId } from "react";
import { Icon } from "./Icon.jsx";

export function useFieldIds(providedId) {
  const generated = useId();
  const id = providedId ?? generated;
  return { id, hintId: `${id}-hint`, errorId: `${id}-error` };
}

/**
 * Inputs are a black rule with text on it. Focus snaps the rule to Swiss Red;
 * there is no glow. Invalid fields keep the red rule at rest so they can be
 * found without tabbing, and the message below says what is wrong in words.
 *
 * `boxed` gives a fully bordered control for the few places (site search) that
 * need a visibly framed field.
 */
export const CONTROL =
  "h-12 w-full rounded-none border-0 border-b-2 border-black bg-transparent px-0 font-sans text-base " +
  "text-black placeholder:text-black/40 transition-colors duration-150 ease-linear " +
  "focus:border-accent focus:outline-none disabled:cursor-not-allowed disabled:opacity-40 " +
  "aria-invalid:border-accent";

export const CONTROL_BOXED =
  "h-12 w-full rounded-none border-2 border-black bg-white px-4 font-sans text-base text-black " +
  "placeholder:text-black/40 transition-colors duration-150 ease-linear " +
  "focus:border-accent focus:outline-none disabled:cursor-not-allowed disabled:opacity-40 " +
  "aria-invalid:border-accent";

export const LABEL = "font-sans text-2xs label-caps text-black";

export function FieldShell({ id, hintId, errorId, label, labelMeta, hint, error, children, className = "" }) {
  return (
    <div className={`flex flex-col gap-2 ${className}`.trim()}>
      {label ? (
        <label className={`${LABEL} flex items-baseline justify-between gap-4`} htmlFor={id}>
          {label}
          {labelMeta ? <span className="font-medium normal-case tracking-normal text-black/60">{labelMeta}</span> : null}
        </label>
      ) : null}
      {children}
      {hint && !error ? (
        <p className="font-sans text-xs text-black/60" id={hintId}>
          {hint}
        </p>
      ) : null}
      {error ? (
        <p className="inline-flex items-center gap-2 font-sans text-xs font-bold text-accent-text" id={errorId}>
          <Icon name="alertTriangle" size={13} strokeWidth={2.5} className="shrink-0" />
          {error}
        </p>
      ) : null}
    </div>
  );
}

export function TextInput({ id: providedId, label, labelMeta, hint, error, boxed = false, className = "", ...rest }) {
  const { id, hintId, errorId } = useFieldIds(providedId);

  return (
    <FieldShell id={id} hintId={hintId} errorId={errorId} label={label} labelMeta={labelMeta} hint={hint} error={error} className={className}>
      <input
        id={id}
        className={boxed ? CONTROL_BOXED : CONTROL}
        aria-invalid={error ? true : undefined}
        aria-describedby={error ? errorId : hint ? hintId : undefined}
        {...rest}
      />
    </FieldShell>
  );
}

export function Select({ id: providedId, label, labelMeta, hint, error, options, className = "", ...rest }) {
  const { id, hintId, errorId } = useFieldIds(providedId);

  return (
    <FieldShell id={id} hintId={hintId} errorId={errorId} label={label} labelMeta={labelMeta} hint={hint} error={error} className={className}>
      <div className="relative">
        <select
          id={id}
          className={`${CONTROL} cursor-pointer appearance-none pr-10`}
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
          size={16}
          strokeWidth={2.5}
          className="pointer-events-none absolute right-0 top-1/2 -translate-y-1/2 text-black"
        />
      </div>
    </FieldShell>
  );
}

/**
 * A checkbox styled as a rectangular toggle. The native input stays in the DOM,
 * visually hidden but focusable, so keyboard, screen readers and form
 * semantics keep working; only its rendering is replaced.
 *
 * Checked is a full inversion to black; hover is the red signal.
 */
export function CheckboxTag({ checked, onChange, children, name, className = "" }) {
  return (
    <label
      className={`group inline-flex h-11 cursor-pointer select-none items-center gap-3 rounded-none border-2
                  border-black px-4 font-sans text-xs label-caps transition-colors duration-150 ease-linear
                  has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-accent has-[:focus-visible]:ring-offset-2
                  hover:border-accent hover:bg-accent hover:text-white
                  ${checked ? "bg-black text-white" : "bg-white text-black"} ${className}`}
    >
      <input className="sr-only" type="checkbox" name={name} checked={checked} onChange={onChange} />
      <span
        className={`grid h-3.5 w-3.5 place-items-center border-2 transition-colors duration-150 ${
          checked ? "border-white bg-white" : "border-current bg-transparent"
        } group-hover:border-white`}
        aria-hidden="true"
      >
        {checked ? <span className="h-1.5 w-1.5 bg-black" /> : null}
      </span>
      {children}
    </label>
  );
}
