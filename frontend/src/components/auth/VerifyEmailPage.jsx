/**
 * Two states behind one route:
 *
 * - arriving from a link with `?token=...`, which is redeemed immediately
 * - arriving from registration with `?sent=1`, the "check your inbox" screen
 */

import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "../ui/Button.jsx";
import { Spinner } from "../ui/Spinner.jsx";
import { TextInput } from "../ui/Field.jsx";
import { AuthForm, AuthShell, FinePrint, FormStatus, SubmitButton, useAuthForm } from "./AuthShell.jsx";
import { authApi } from "../../lib/authApi.js";
import { useAuth } from "../../context/AuthContext.jsx";
import { Link, useRouter } from "../../lib/router.jsx";

export function VerifyEmailPage() {
  const { query, navigate } = useRouter();
  const { refresh } = useAuth();
  const token = query.get("token");
  const presetEmail = query.get("email") || "";

  const [state, setState] = useState(token ? "verifying" : "pending");
  const [message, setMessage] = useState("");
  // A link click can render twice under StrictMode; without this the token is
  // redeemed once and the second attempt reports "already used".
  const redeemed = useRef(false);

  useEffect(() => {
    if (!token || redeemed.current) return;
    redeemed.current = true;

    authApi
      .verifyEmail(token)
      .then((payload) => {
        setState("verified");
        setMessage(payload?.message || "Your email address is confirmed.");
        refresh();
      })
      .catch((error) => {
        setState("failed");
        setMessage(error?.message || "This link is invalid or has expired.");
      });
  }, [token, refresh]);

  if (state === "verifying") {
    return (
      <AuthShell number="03" eyebrow="Confirm" title="Confirming your email.">
        <p className="flex items-center gap-3 font-sans text-xs label-caps text-black" role="status" aria-live="polite">
          <Spinner size={16} />
          Checking your link…
        </p>
      </AuthShell>
    );
  }

  if (state === "verified") {
    return (
      <AuthShell number="03" eyebrow="Confirm" title="Email confirmed.">
        <FormStatus success={message} />
        <Button variant="primary" size="lg" block onClick={() => navigate("/signin")}>
          Continue to sign in
        </Button>
      </AuthShell>
    );
  }

  if (state === "failed") {
    return (
      <AuthShell number="03" eyebrow="Confirm" title="That link did not work.">
        <FormStatus error={message} />
        <ResendForm presetEmail={presetEmail} />
        <FinePrint>
          Already confirmed? <Link to="/signin">Sign in</Link>
        </FinePrint>
      </AuthShell>
    );
  }

  return (
    <AuthShell
      number="03"
      eyebrow="Confirm"
      title="Check your email."
      description={
        presetEmail
          ? `If ${presetEmail} needs confirming, a link is on its way. It expires in 24 hours.`
          : "If that address needs confirming, a link is on its way. It expires in 24 hours."
      }
    >
      <FinePrint>Nothing arrived? Check your spam folder, then request another link.</FinePrint>
      <ResendForm presetEmail={presetEmail} />
      <FinePrint>
        <Link to="/signin">Back to sign in</Link>
      </FinePrint>
    </AuthShell>
  );
}

function ResendForm({ presetEmail }) {
  const [email, setEmail] = useState(presetEmail);

  const form = useAuthForm(
    useCallback(async () => {
      const payload = await authApi.resendVerification(email);
      return { message: payload?.message || "If that address needs confirming, we have sent a link." };
    }, [email]),
  );

  return (
    <AuthForm onSubmit={form.onSubmit}>
      <FormStatus error={form.error} success={form.success} />
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
        Send a new link
      </SubmitButton>
    </AuthForm>
  );
}
