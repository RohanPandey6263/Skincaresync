/**
 * Shared chrome and form primitives for the authentication screens.
 *
 * Accessibility notes that apply to every form built on this:
 * - one <h1> per screen, and the panel is labelled by it
 * - errors are announced through role="alert", not colour alone
 * - the submit button is disabled while in flight, which is what stops a double
 *   submission creating two accounts or two reset emails
 * - autocomplete attributes are set so password managers behave
 */

import { useCallback, useState } from "react";
import { Button } from "../ui/Button.jsx";
import { Callout } from "../ui/Feedback.jsx";
import { Icon } from "../ui/Icon.jsx";
import { FieldShell, useFieldIds } from "../ui/Field.jsx";
import { Link } from "../../lib/router.jsx";

export function AuthShell({ title, description, children, footer, icon = "shield" }) {
  return (
    <main className="authPage" id="main">
      <div className="authCard">
        <Link to="/" className="authCard__brand">
          <span className="authCard__mark" aria-hidden="true">
            <Icon name={icon} size={18} />
          </span>
          SkincareSync
        </Link>
        <h1 className="authCard__title">{title}</h1>
        {description ? <p className="authCard__description">{description}</p> : null}
        <div className="authCard__body">{children}</div>
        {footer ? <div className="authCard__footer">{footer}</div> : null}
      </div>
    </main>
  );
}

/**
 * A password input with a reveal toggle.
 *
 * `autoComplete` is required rather than defaulted: the correct value differs
 * per screen ("new-password" when creating, "current-password" when signing in)
 * and getting it wrong makes password managers save the wrong thing.
 */
export function PasswordInput({
  id: providedId,
  label,
  hint,
  error,
  autoComplete,
  value,
  onChange,
  ...rest
}) {
  const { id, hintId, errorId } = useFieldIds(providedId);
  const [revealed, setRevealed] = useState(false);

  return (
    <FieldShell id={id} hintId={hintId} errorId={errorId} label={label} hint={hint} error={error}>
      <div className="passwordField">
        <input
          id={id}
          className="input passwordField__input"
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
          className="passwordField__toggle"
          onClick={() => setRevealed((current) => !current)}
          aria-pressed={revealed}
          // The label says what the control does, not what the state is.
          aria-label={revealed ? "Hide password" : "Show password"}
        >
          <Icon name={revealed ? "eyeOff" : "eye"} size={16} />
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

/**
 * Submission state for an auth form.
 *
 * Holds the in-flight flag, the banner message and per-field errors from the
 * server, and refuses to run a second submission while one is outstanding.
 */
export function useAuthForm(submit) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [fieldErrors, setFieldErrors] = useState({});

  const onSubmit = useCallback(
    async (event) => {
      event?.preventDefault();
      if (pending) return; // guards against a double click or a double Enter
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
