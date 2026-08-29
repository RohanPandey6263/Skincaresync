import { useState } from "react";
import { TextInput } from "../ui/Field.jsx";
import { AuthShell, FormStatus, PasswordInput, SubmitButton, useAuthForm } from "./AuthShell.jsx";
import { OAUTH_ERRORS, SocialButtons } from "./SocialButtons.jsx";
import { useAuth } from "../../context/AuthContext.jsx";
import { Link, useRouter } from "../../lib/router.jsx";

export function SignInPage() {
  const { signIn } = useAuth();
  const { navigate, query } = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  // The server validates this again and falls back to "/" if it is not a
  // site-relative path, so a crafted ?next= cannot bounce the user off-site.
  const next = query.get("next") || "";

  // Social sign-in fails by redirecting here with a short code. Only known codes
  // are rendered, so nothing a provider returns reaches the page.
  const oauthError = OAUTH_ERRORS[query.get("error")] || "";

  const form = useAuthForm(async () => {
    const payload = await signIn({ email, password, next: next || null });
    navigate(payload.redirect_to || "/", { replace: true });
    return null;
  });

  return (
    <AuthShell
      title="Sign in"
      description="Sign in to save routines and manage your account."
      footer={
        <p>
          New here? <Link to="/register">Create an account</Link>
        </p>
      }
    >
      <SocialButtons next={next} label="Continue with" />

      <form onSubmit={form.onSubmit} noValidate>
        <FormStatus error={form.error || oauthError} />

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

        <PasswordInput
          label="Password"
          name="password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          autoComplete="current-password"
          required
          error={form.fieldErrors.password}
        />

        <div className="authCard__aside">
          <Link to="/forgot-password" className="linkAction">
            Forgot your password?
          </Link>
        </div>

        <SubmitButton pending={form.pending} pendingLabel="Signing in">
          Sign in
        </SubmitButton>
      </form>
    </AuthShell>
  );
}
