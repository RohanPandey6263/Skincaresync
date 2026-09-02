import { useState } from "react";
import { TextInput } from "../ui/Field.jsx";
import { AuthForm, AuthShell, FormStatus, PasswordInput, SubmitButton, useAuthForm } from "./AuthShell.jsx";
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

  // Only known OAuth error codes are rendered, so nothing a provider returns reaches the page.
  const oauthError = OAUTH_ERRORS[query.get("error")] || "";

  const form = useAuthForm(async () => {
    const payload = await signIn({ email, password, next: next || null });
    navigate(payload.redirect_to || "/", { replace: true });
    return null;
  });

  return (
    <AuthShell
      number="01"
      eyebrow="Sign in"
      title="Welcome back."
      description="Sign in to manage your account and security settings. Accounts are optional for analysis."
      footer={
        <p>
          New here? <Link to="/register">Create an account</Link>
        </p>
      }
    >
      <SocialButtons next={next} label="Continue with" />

      <AuthForm onSubmit={form.onSubmit}>
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

        <div className="flex justify-end">
          <Link to="/forgot-password" className="font-sans text-xs label-caps text-black underline decoration-2 underline-offset-4 hover:text-accent-text">
            Forgot your password?
          </Link>
        </div>

        <SubmitButton pending={form.pending} pendingLabel="Signing in">
          Sign in
        </SubmitButton>
      </AuthForm>
    </AuthShell>
  );
}
