/** Account and security settings: password, connected accounts, and closing the account. */

import { useCallback, useEffect, useState } from "react";
import { Panel } from "../ui/Panel.jsx";
import { Icon, Logomark } from "../ui/Icon.jsx";
import { AnchorButton, Button } from "../ui/Button.jsx";
import { Badge } from "../ui/Badge.jsx";
import { Callout } from "../ui/Feedback.jsx";
import { TextInput } from "../ui/Field.jsx";
import { Modal } from "../ui/Modal.jsx";
import { Container, Headline, SectionLabel } from "../ui/Section.jsx";
import { AuthForm, FormStatus, PasswordInput, SubmitButton, useAuthForm } from "./AuthShell.jsx";
import { authApi } from "../../lib/authApi.js";
import { API_BASE } from "../../lib/api.js";
import { useAuth } from "../../context/AuthContext.jsx";
import { Link, useRouter } from "../../lib/router.jsx";
import { useToast } from "../ui/Toaster.jsx";

const MIN_PASSWORD_LENGTH = 12;

export function AccountSecurityPage() {
  const { user, refresh, signOut } = useAuth();
  const { navigate } = useRouter();
  const { notify } = useToast();

  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [signingOut, setSigningOut] = useState(false);

  async function handleSignOut() {
    setSigningOut(true);
    try {
      await signOut();
      notify({ tone: "info", title: "Signed out" });
      navigate("/", { replace: true });
    } catch (error) {
      notify({ tone: "danger", title: "Could not sign out", description: error.message });
    } finally {
      setSigningOut(false);
    }
  }

  return (
    <main className="flex-1 bg-paper" id="main" tabIndex={-1}>
      {/* The account page is reached from a menu, so it carries its own way back. */}
      <div className="border-b-4 border-ink">
        <Container className="flex h-20 items-center justify-between gap-6">
          <Link
            to="/"
            className="flex items-center gap-3 text-ink no-underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral-deep focus-visible:ring-offset-4"
          >
            <Logomark size={36} />
            <span className="hidden font-sans text-lg font-black uppercase tracking-tighter sm:block">SkincareSync</span>
          </Link>
          <div className="flex items-center gap-3">
            <Button variant="secondary" size="sm" icon="logOut" loading={signingOut} onClick={handleSignOut}>
              Log out
            </Button>
            <Link
              to="/"
              className="grid h-11 w-11 place-items-center border-2 border-ink text-ink transition-colors duration-150 hover:bg-ink hover:text-paper focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-coral-deep focus-visible:ring-offset-2"
              aria-label="Exit account settings"
            >
              <Icon name="close" size={20} strokeWidth={2.5} />
            </Link>
          </div>
        </Container>
      </div>

      <Container className="flex flex-col gap-12 py-12 md:py-16">
        <header className="grid grid-cols-1 gap-6 border-b-4 border-ink pb-10 lg:grid-cols-12">
          <div className="flex flex-col gap-5 lg:col-span-8">
            <SectionLabel number="00">Account</SectionLabel>
            <Headline as="h1" size="display">
              Account &amp; security
            </Headline>
          </div>
          <div className="flex flex-col justify-end gap-3 lg:col-span-4">
            <p className="font-sans text-base font-medium text-ink">{user?.email}</p>
            <div className="flex flex-wrap gap-2">
              {user?.email_verified ? (
                <Badge tone="ok" size="sm">
                  Verified
                </Badge>
              ) : (
                <Badge tone="warn" size="sm">
                  Unverified
                </Badge>
              )}
              {user?.role === "admin" ? (
                <Badge tone="info" size="sm">
                  Administrator
                </Badge>
              ) : null}
            </div>
          </div>
        </header>

        <div className="flex flex-col gap-8">
          {!user?.email_verified ? <UnverifiedNotice email={user?.email} /> : null}

          <ChangePasswordPanel hasPassword={user?.has_password ?? true} />

          <ConnectedAccountsPanel hasPassword={user?.has_password ?? true} />

          <Panel
            number="03"
            eyebrow="Danger"
            title="Close your account"
            description="Deactivating is reversible. Deleting removes your personal details permanently."
            className="border-coral md:border-coral"
          >
            <div className="flex flex-wrap gap-3">
              <Button
                variant="secondary"
                onClick={async () => {
                  await authApi.deactivate();
                  notify({ tone: "info", title: "Account deactivated" });
                  await refresh();
                  navigate("/", { replace: true });
                }}
              >
                Deactivate account
              </Button>
              <Button variant="accent" onClick={() => setConfirmingDelete(true)}>
                Delete account
              </Button>
            </div>
          </Panel>
        </div>

        <DeleteAccountDialog
          open={confirmingDelete}
          onClose={() => setConfirmingDelete(false)}
          onDeleted={async () => {
            notify({ tone: "info", title: "Account deleted" });
            await refresh();
            navigate("/", { replace: true });
          }}
        />
      </Container>
    </main>
  );
}

function UnverifiedNotice({ email }) {
  const [sent, setSent] = useState(false);
  const form = useAuthForm(
    useCallback(async () => {
      await authApi.resendVerification(email);
      setSent(true);
      return null;
    }, [email]),
  );

  return (
    <Callout tone="warn" icon="alertTriangle" title="Confirm your email address">
      Some features stay locked until you confirm {email}.
      {sent ? (
        <p role="status">A new link is on its way.</p>
      ) : (
        <p>
          <Button variant="secondary" size="sm" onClick={form.onSubmit} loading={form.pending}>
            Resend confirmation link
          </Button>
        </p>
      )}
    </Callout>
  );
}

function ConnectedAccountsPanel({ hasPassword }) {
  const { notify } = useToast();
  const { query } = useRouter();
  const [providers, setProviders] = useState([]);
  const [linked, setLinked] = useState(null);
  const [busy, setBusy] = useState(null);

  const load = useCallback(async () => {
    try {
      setLinked(await authApi.listIdentities());
    } catch {
      setLinked([]);
    }
  }, []);

  useEffect(() => {
    fetch(`${API_BASE}/api/auth/oauth/providers`, { credentials: "include" })
      .then((response) => (response.ok ? response.json() : []))
      .then(setProviders)
      .catch(() => setProviders([]));
    load();
  }, [load]);

  const justLinked = query.get("linked");

  if (!providers.length) return null;

  const linkedKeys = new Set((linked || []).map((identity) => identity.provider));
  // Disconnecting the only way in would lock the account out of itself.
  const canUnlink = hasPassword || linkedKeys.size > 1;

  return (
    <Panel number="02" eyebrow="Providers" title="Connected accounts" description="Sign in with a provider instead of a password." padding="none">
      {justLinked || (!hasPassword && linkedKeys.size === 1) ? (
        <div className="flex flex-col gap-4 p-6 md:p-8">
          {justLinked ? <FormStatus success={`Your ${justLinked} account is connected.`} /> : null}
          {!hasPassword && linkedKeys.size === 1 ? (
            <Callout tone="info" icon="info">
              This is your only way to sign in. Set a password above before disconnecting it.
            </Callout>
          ) : null}
        </div>
      ) : null}

      <ul className="flex flex-col divide-y-2 divide-ink">
        {providers.map((provider) => {
          const identity = (linked || []).find((item) => item.provider === provider.key);
          return (
            <li key={provider.key} className="flex flex-wrap items-center justify-between gap-4 px-6 py-5 md:px-8">
              <div className="flex flex-col gap-1">
                <p className="font-sans text-base font-black uppercase tracking-tight text-ink">{provider.display_name}</p>
                <p className="font-sans text-xs text-ink/60">
                  {identity ? `Connected${identity.email ? ` as ${identity.email}` : ""}` : "Not connected"}
                </p>
              </div>
              {identity ? (
                <Button
                  variant="secondary"
                  size="sm"
                  disabled={!canUnlink}
                  loading={busy === provider.key}
                  onClick={async () => {
                    setBusy(provider.key);
                    try {
                      await authApi.unlinkIdentity(provider.key);
                      notify({ tone: "ok", title: `${provider.display_name} disconnected` });
                      await load();
                    } catch (error) {
                      notify({ tone: "danger", title: "Could not disconnect", description: error.message });
                    } finally {
                      setBusy(null);
                    }
                  }}
                >
                  Disconnect
                </Button>
              ) : (
                // A link, not a fetch: OAuth needs a top-level navigation.
                <AnchorButton variant="primary" size="sm" href={`${API_BASE}/api/auth/oauth/${provider.key}/link`}>
                  Connect
                </AnchorButton>
              )}
            </li>
          );
        })}
      </ul>
    </Panel>
  );
}

/**
 * Password settings. An account created through a provider has no password to
 * change, so it gets a single button; the form appears once asked for.
 */
function ChangePasswordPanel({ hasPassword }) {
  const { notify } = useToast();
  const [creating, setCreating] = useState(false);
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [confirmation, setConfirmation] = useState("");

  const mismatch = confirmation.length > 0 && next !== confirmation;

  const form = useAuthForm(
    useCallback(async () => {
      if (next !== confirmation) {
        throw Object.assign(new Error("Both passwords must match."), {
          fieldErrors: { confirmation: "Both passwords must match." },
        });
      }
      const payload = await authApi.changePassword(current, next);
      setCurrent("");
      setNext("");
      setConfirmation("");
      notify({ tone: "ok", title: "Password updated" });
      return { message: payload?.message };
    }, [current, next, confirmation, notify]),
  );

  if (!hasPassword && !creating) {
    return (
      <Panel number="01" eyebrow="Password" title="Password" description="You sign in through a connected account. A password is optional.">
        <Button variant="secondary" onClick={() => setCreating(true)}>
          Create a password
        </Button>
      </Panel>
    );
  }

  return (
    <Panel
      number="01"
      eyebrow="Password"
      title={hasPassword ? "Password" : "Create a password"}
      description={hasPassword ? "Other devices are signed out when you change it." : "Adds a second way into your account, alongside your connected one."}
    >
      <div className="max-w-xl">
        <AuthForm onSubmit={form.onSubmit}>
          <FormStatus error={form.error} success={form.success} />

          {hasPassword ? (
            <PasswordInput
              label="Current password"
              value={current}
              onChange={(event) => setCurrent(event.target.value)}
              autoComplete="current-password"
              required
              error={form.fieldErrors.current_password}
            />
          ) : null}
          <PasswordInput
            label="New password"
            value={next}
            onChange={(event) => setNext(event.target.value)}
            autoComplete="new-password"
            required
            minLength={MIN_PASSWORD_LENGTH}
            hint={`At least ${MIN_PASSWORD_LENGTH} characters.`}
            error={form.fieldErrors.password}
          />
          <PasswordInput
            label="Confirm new password"
            value={confirmation}
            onChange={(event) => setConfirmation(event.target.value)}
            autoComplete="new-password"
            required
            error={mismatch ? "Both passwords must match." : form.fieldErrors.confirmation}
          />

          <SubmitButton pending={form.pending} pendingLabel="Saving">
            {hasPassword ? "Update password" : "Create password"}
          </SubmitButton>
        </AuthForm>
      </div>
    </Panel>
  );
}

function DeleteAccountDialog({ open, onClose, onDeleted }) {
  const [password, setPassword] = useState("");
  const [confirmText, setConfirmText] = useState("");

  const form = useAuthForm(
    useCallback(async () => {
      await authApi.deleteAccount(password);
      await onDeleted();
      return null;
    }, [password, onDeleted]),
  );

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Delete your account"
      description="This removes your personal details permanently and cannot be undone."
    >
      <AuthForm onSubmit={form.onSubmit}>
        <FormStatus error={form.error} />
        <PasswordInput
          label="Current password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          autoComplete="current-password"
          required
        />
        <TextInput
          label="Type DELETE to confirm"
          value={confirmText}
          onChange={(event) => setConfirmText(event.target.value)}
          autoComplete="off"
          required
        />
        <div className="flex flex-wrap justify-end gap-3">
          <Button variant="secondary" type="button" onClick={onClose}>
            Cancel
          </Button>
          <Button
            type="submit"
            variant="accent"
            loading={form.pending}
            disabled={confirmText.trim().toUpperCase() !== "DELETE" || !password}
          >
            Delete my account
          </Button>
        </div>
      </AuthForm>
    </Modal>
  );
}
