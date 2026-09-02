import { useState } from "react";
import { TextInput } from "../ui/Field.jsx";
import { AuthForm, AuthShell, FinePrint, FormStatus, PasswordInput, SubmitButton, useAuthForm } from "./AuthShell.jsx";
import { SocialButtons } from "./SocialButtons.jsx";
import { authApi } from "../../lib/authApi.js";
import { Link, useRouter } from "../../lib/router.jsx";

const MIN_PASSWORD_LENGTH = 12;

export function RegisterPage() {
  const { navigate } = useRouter();
  const [email, setEmail] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [password, setPassword] = useState("");

  const form = useAuthForm(async () => {
    await authApi.register({ email, password, display_name: displayName || null });
    // The response is the same whether or not the address was already
    // registered, so the next screen says "check your email" either way.
    navigate(`/verify-email?sent=1&email=${encodeURIComponent(email)}`, { replace: true });
    return null;
  });

  const tooShort = password.length > 0 && password.length < MIN_PASSWORD_LENGTH;

  return (
    <AuthShell
      number="02"
      eyebrow="Register"
      title="Create your account."
      description="Manage your security settings and pick up where you left off."
      footer={
        <p>
          Already have an account? <Link to="/signin">Sign in</Link>
        </p>
      }
    >
      <SocialButtons label="Sign up with" />

      <AuthForm onSubmit={form.onSubmit}>
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

        <TextInput
          label="Name"
          labelMeta="Optional"
          hint="Shown on your account page."
          name="name"
          value={displayName}
          onChange={(event) => setDisplayName(event.target.value)}
          autoComplete="name"
          maxLength={80}
          error={form.fieldErrors.display_name}
        />

        <PasswordInput
          label="Password"
          name="new-password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          autoComplete="new-password"
          required
          minLength={MIN_PASSWORD_LENGTH}
          hint={`At least ${MIN_PASSWORD_LENGTH} characters. A short phrase works well.`}
          error={form.fieldErrors.password || (tooShort ? `Use at least ${MIN_PASSWORD_LENGTH} characters.` : undefined)}
        />

        <SubmitButton pending={form.pending} pendingLabel="Creating account">
          Create account
        </SubmitButton>

        <FinePrint>We will send a confirmation link to your email address.</FinePrint>
      </AuthForm>
    </AuthShell>
  );
}
