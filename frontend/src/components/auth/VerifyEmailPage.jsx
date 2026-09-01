/**
 * Two states behind one route:
 *
 * - arriving from a link with `?token=...`, which is redeemed immediately
 * - arriving from registration with `?sent=1`, which is the "check your inbox"
 *   holding screen with a resend control
 */

import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "../ui/Button.jsx";
import { Spinner } from "../ui/Spinner.jsx";
import { TextInput } from "../ui/Field.jsx";
import { AuthShell, FormStatus, SubmitButton, useAuthForm } from "./AuthShell.jsx";
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
        // Picks up email_verified if this browser is already signed in.
        refresh();
      })
      .catch((error) => {
        setState("failed");
        setMessage(error?.message || "This link is invalid or has expired.");
      });
  }, [token, refresh]);

  if (state === "verifying") {
    return (
      <AuthShell title="Confirming your email">
        <p className="authCard__pending" role="status" aria-live="polite">
          <Spinner size={16} />
          Checking your link…
        </p>
      </AuthShell>
    );
  }

  if (state === "verified") {
    return (
      <AuthShell title="Email confirmed">
        <FormStatus success={message} />
        <Button variant="primary" size="lg" block onClick={() => navigate("/signin")}>
          Continue to sign in
        </Button>
      </AuthShell>
    );
  }

  if (state === "failed") {
    return (
      <AuthShell title="That link did not work">
        <FormStatus error={message} />
        <ResendForm presetEmail={presetEmail} />
        <p className="authCard__fineprint">
          Already confirmed? <Link to="/signin">Sign in</Link>
        </p>
      </AuthShell>
    );
  }

  return (
    <AuthShell
      title="Check your email"
      description={
        presetEmail
          ? `If ${presetEmail} needs confirming, a link is on its way. It expires in 24 hours.`
          : "If that address needs confirming, a link is on its way. It expires in 24 hours."
      }
     
    >
      <p className="authCard__fineprint">
        Nothing arrived? Check your spam folder, then request another link.
      </p>
      <ResendForm presetEmail={presetEmail} />
      <p className="authCard__fineprint">
        <Link to="/signin">Back to sign in</Link>
      </p>
    </AuthShell>
  );
}

function ResendForm({ presetEmail }) {
  const [email, setEmail] = useState(presetEmail);

  const form = useAuthForm(
    useCallback(async () => {
      const payload = await authApi.resendVerification(email);
      // Same message regardless of whether the address exists.
      return { message: payload?.message || "If that address needs confirming, we have sent a link." };
    }, [email]),
  );

  return (
    <form onSubmit={form.onSubmit} noValidate>
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
    </form>
  );
}
