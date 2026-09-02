/**
 * Shared chrome and form primitives for the authentication screens.
 *
 * The shell is asymmetric: a black column carries the title as an image made
 * of words; the white column carries the form. On a phone the black column
 * becomes a band above the form.
 *
 * Accessibility notes that apply to every form built on this:
 * - one <h1> per screen, and the panel is labelled by it
 * - errors are announced through role="alert", not colour alone
 * - the submit button is disabled while in flight
 * - autocomplete attributes are set so password managers behave
 */

import { useCallback, useState } from "react";
import { Button } from "../ui/Button.jsx";
import { Callout } from "../ui/Feedback.jsx";
import { Icon, Logomark } from "../ui/Icon.jsx";
import { FieldShell, CONTROL, useFieldIds } from "../ui/Field.jsx";
import { Link } from "../../lib/router.jsx";

export function AuthShell({ number = "01", eyebrow = "Account", title, description, children, footer }) {
  return (
    <main className="grid min-h-dvh grid-cols-1 lg:grid-cols-12" id="main">
      <div className="flex flex-col justify-between gap-12 bg-ink px-6 py-8 text-paper md:px-12 md:py-12 lg:col-span-5 lg:min-h-dvh lg:sticky lg:top-0">
        <div className="flex items-center justify-between">
          <Link
            to="/"
            className="flex items-center gap-3 text-paper no-underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral-deep focus-visible:ring-offset-2 focus-visible:ring-offset-ink"
          >
            <Logomark size={36} />
            <span className="font-sans text-lg font-black uppercase tracking-tighter">SkincareSync</span>
          </Link>
          <Link
            to="/"
            className="grid h-11 w-11 place-items-center border-2 border-paper text-paper transition-colors duration-150 hover:bg-paper hover:text-ink focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral-deep focus-visible:ring-offset-2 focus-visible:ring-offset-ink lg:hidden"
            aria-label="Exit and return to SkincareSync"
          >
            <Icon name="close" size={20} strokeWidth={2.5} />
          </Link>
        </div>

        <div className="flex flex-col gap-6">
          <p className="flex items-center gap-3 font-sans text-xs label-caps text-paper">
            <span className="text-coral-deep">{number}.</span>
            {eyebrow}
          </p>
          <h1 className="font-sans text-display font-black uppercase text-paper">{title}</h1>
        </div>

        <p className="hidden font-sans text-2xs label-caps text-paper/50 lg:block">Objective · Cited · Deterministic</p>
      </div>

      <div className="relative flex flex-col gap-8 px-6 py-10 md:px-12 md:py-16 lg:col-span-7 lg:px-20">
        <Link
          to="/"
          className="absolute right-6 top-6 hidden h-11 w-11 place-items-center border-2 border-ink text-ink transition-colors duration-150 hover:bg-ink hover:text-paper focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral-deep focus-visible:ring-offset-2 lg:grid"
          aria-label="Exit and return to SkincareSync"
        >
          <Icon name="close" size={20} strokeWidth={2.5} />
        </Link>
        <div className="flex w-full max-w-xl flex-col gap-8">
          {description ? <p className="font-sans text-base leading-relaxed text-ink/70">{description}</p> : null}
          <div className="flex flex-col gap-6">{children}</div>
          {footer ? (
            <div className="border-t-2 border-ink pt-6 font-sans text-sm text-ink [&_a]:font-bold [&_a]:underline [&_a]:decoration-2 [&_a]:underline-offset-4 [&_a:hover]:text-coral-deep">
              {footer}
            </div>
          ) : null}
        </div>
      </div>
    </main>
  );
}

/** Body copy under a form: small, objective, black at reduced alpha. */
export function FinePrint({ children }) {
  return <p className="font-sans text-sm leading-relaxed text-ink/70 [&_a]:font-bold [&_a]:text-ink [&_a]:underline [&_a]:decoration-2 [&_a]:underline-offset-4 [&_a:hover]:text-coral-deep">{children}</p>;
}

/**
 * A password input with a reveal toggle.
 *
 * `autoComplete` is required rather than defaulted: the correct value differs
 * per screen and getting it wrong makes password managers save the wrong thing.
 */
export function PasswordInput({ id: providedId, label, hint, error, autoComplete, value, onChange, ...rest }) {
  const { id, hintId, errorId } = useFieldIds(providedId);
  const [revealed, setRevealed] = useState(false);

  return (
    <FieldShell id={id} hintId={hintId} errorId={errorId} label={label} hint={hint} error={error}>
      <div className="relative">
        <input
          id={id}
          className={`${CONTROL} pr-12`}
          type={revealed ? "text" : "password"}
          autoComplete={autoComplete}
          value={value}
          onChange={onChange}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? errorId : hint ? hintId : undefined}
          {...rest}
        />
        <button
          type="button"
          className="absolute right-0 top-1/2 grid h-10 w-10 -translate-y-1/2 place-items-center text-ink transition-colors duration-150 hover:bg-ink hover:text-paper focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral-deep"
          onClick={() => setRevealed((current) => !current)}
          aria-pressed={revealed}
          aria-label={revealed ? "Hide password" : "Show password"}
        >
          <Icon name={revealed ? "eyeOff" : "eye"} size={18} strokeWidth={2.25} />
        </button>
      </div>
    </FieldShell>
  );
}

/** A live-region banner. Errors interrupt; successes wait their turn. */
export function FormStatus({ error, success }) {
  if (!error && !success) return null;
  return (
    <div role={error ? "alert" : "status"} aria-live={error ? "assertive" : "polite"}>
      <Callout tone={error ? "danger" : "ok"} icon={error ? "alertTriangle" : "checkCircle"}>
        {error || success}
      </Callout>
    </div>
  );
}

export function SubmitButton({ pending, children, pendingLabel, ...rest }) {
  return (
    <Button type="submit" variant="primary" size="lg" block loading={pending} {...rest}>
      {pending ? pendingLabel || "Working" : children}
    </Button>
  );
}

/** Standard vertical rhythm for an auth form. */
export function AuthForm({ onSubmit, children }) {
  return (
    <form onSubmit={onSubmit} noValidate className="flex flex-col gap-6">
      {children}
    </form>
  );
}

/**
 * Submission state for an auth form. Holds the in-flight flag, the banner
 * message and per-field errors, and refuses a second submission while one is
 * outstanding.
 */
export function useAuthForm(submit) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [fieldErrors, setFieldErrors] = useState({});

  const onSubmit = useCallback(
    async (event) => {
      event?.preventDefault();
      if (pending) return;
      setPending(true);
      setError("");
      setSuccess("");
      setFieldErrors({});
      try {
        const result = await submit();
        if (result?.message) setSuccess(result.message);
        return result;
      } catch (caught) {
        setError(caught?.message || "Something went wrong. Please try again.");
        setFieldErrors(caught?.fieldErrors || {});
        return null;
      } finally {
        setPending(false);
      }
    },
    [pending, submit],
  );

  return { pending, error, success, fieldErrors, onSubmit, setError, setSuccess };
}
