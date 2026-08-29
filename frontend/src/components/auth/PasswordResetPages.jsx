/** Forgot-password request, and the reset screen the emailed link lands on. */

import { useCallback, useState } from "react";
import { Button } from "../ui/Button.jsx";
import { TextInput } from "../ui/Field.jsx";
import { AuthShell, FormStatus, PasswordInput, SubmitButton, useAuthForm } from "./AuthShell.jsx";
import { authApi } from "../../lib/authApi.js";
import { Link, useRouter } from "../../lib/router.jsx";

const MIN_PASSWORD_LENGTH = 12;

export function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);

  const form = useAuthForm(
    useCallback(async () => {
      const payload = await authApi.forgotPassword(email);
      setSent(true);
      return { message: payload?.message };
    }, [email]),
  );

  if (sent) {
    return (
      <AuthShell title="Check your email" icon="mail">
        {/* Deliberately does not say whether an account exists. */}
        <FormStatus success={form.success || "If an account exists for that address, we have sent reset instructions."} />
        <p className="authCard__fineprint">
          The link expires in one hour and can be used once. Check your spam folder if nothing
          arrives.
        </p>
        <p className="authCard__fineprint">
          <Link to="/signin">Back to sign in</Link>
        </p>
      </AuthShell>
    );
  }

  return (
    <AuthShell
      title="Reset your password"
      description="Enter your email address and we will send you a link to choose a new password."
      footer={
        <p>
          Remembered it? <Link to="/signin">Sign in</Link>
        </p>
      }
    >
      <form onSubmit={form.onSubmit} noValidate>
        <FormStatus error={form.error} />
        <TextInput
          label="Email"
          type="email"
          name="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          autoComplete="username"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck="false"
          inputMode="email"
          required
          error={form.fieldErrors.email}
          placeholder="you@example.com"
        />
        <SubmitButton pending={form.pending} pendingLabel="Sending">
          Send reset link
        </SubmitButton>
      </form>
    </AuthShell>
  );
}

export function ResetPasswordPage() {
  const { query, navigate } = useRouter();
  const token = query.get("token");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [done, setDone] = useState(false);

  const mismatch = confirmation.length > 0 && password !== confirmation;
  const tooShort = password.length > 0 && password.length < MIN_PASSWORD_LENGTH;

  const form = useAuthForm(
    useCallback(async () => {
      if (password !== confirmation) {
        throw Object.assign(new Error("Both passwords must match."), {
          fieldErrors: { confirmation: "Both passwords must match." },
        });
      }
      const payload = await authApi.resetPassword(token, password);
      setDone(true);
      return { message: payload?.message };
    }, [token, password, confirmation]),
  );

  if (!token) {
    return (
      <AuthShell title="That link is incomplete" icon="alertTriangle">
        <FormStatus error="This reset link is missing its token. Request a new one." />
        <Button variant="primary" size="lg" block onClick={() => navigate("/forgot-password")}>
          Request a new link
        </Button>
      </AuthShell>
    );
  }

  if (done) {
    return (
      <AuthShell title="Password updated" icon="checkCircle">
        <FormStatus success={form.success || "Your password is updated and all devices were signed out."} />
        <Button variant="primary" size="lg" block onClick={() => navigate("/signin")}>
          Sign in with your new password
        </Button>
      </AuthShell>
    );
  }

  return (
    <AuthShell
      title="Choose a new password"
      description="For your security, every signed-in device will be signed out."
    >
      <form onSubmit={form.onSubmit} noValidate>
        <FormStatus error={form.error} />

        <PasswordInput
          label="New password"
          name="new-password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          autoComplete="new-password"
          required
          minLength={MIN_PASSWORD_LENGTH}
          hint={`At least ${MIN_PASSWORD_LENGTH} characters.`}
          error={form.fieldErrors.password || (tooShort ? `Use at least ${MIN_PASSWORD_LENGTH} characters.` : undefined)}
        />

        <PasswordInput
          label="Confirm new password"
          name="confirm-password"
          value={confirmation}
          onChange={(event) => setConfirmation(event.target.value)}
          autoComplete="new-password"
          required
          error={form.fieldErrors.confirmation || (mismatch ? "Both passwords must match." : undefined)}
        />

        <SubmitButton pending={form.pending} pendingLabel="Updating">
          Update password
        </SubmitButton>
      </form>
    </AuthShell>
  );
}
