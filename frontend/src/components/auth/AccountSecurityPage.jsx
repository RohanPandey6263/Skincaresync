/** Account and security settings: password, connected accounts, and closing the account. */

import { useCallback, useEffect, useState } from "react";
import { Panel } from "../ui/Panel.jsx";
import { Icon, Logomark } from "../ui/Icon.jsx";
import { Button } from "../ui/Button.jsx";
import { Badge } from "../ui/Badge.jsx";
import { Callout } from "../ui/Feedback.jsx";
import { TextInput } from "../ui/Field.jsx";
import { Modal } from "../ui/Modal.jsx";
import { FormStatus, PasswordInput, SubmitButton, useAuthForm } from "./AuthShell.jsx";
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
    <main className="page accountPage" id="main" tabIndex={-1}>
      <div className="container">
        {/* The account page is reached from a menu, not from the site chrome,
            so it carries its own way back: the mark returns home, the cross
            leaves without changing anything. */}
        <div className="pageBar">
          <Link to="/" className="pageBar__brand">
            <span className="pageBar__mark">
              <Logomark size={38} />
            </span>
            SkincareSync
          </Link>
          <div className="pageBar__actions">
            <Button
              variant="ghost"
              size="sm"
              icon="logOut"
              loading={signingOut}
              onClick={handleSignOut}
            >
              Log out
            </Button>
            <Link to="/" className="pageBar__exit" aria-label="Exit account settings">
              <Icon name="close" size={18} />
            </Link>
          </div>
        </div>

        <header className="accountPage__header">
          <h1>Account &amp; security</h1>
          <p className="accountPage__subtitle">
            {user?.email}
            {user?.email_verified ? (
              <Badge tone="ok" size="sm">Verified</Badge>
            ) : (
              <Badge tone="warn" size="sm">Unverified</Badge>
            )}
            {user?.role === "admin" ? <Badge tone="info" size="sm">Administrator</Badge> : null}
          </p>
        </header>

        <div className="accountPage__stack">
          {!user?.email_verified ? <UnverifiedNotice email={user?.email} /> : null}

          <ChangePasswordPanel hasPassword={user?.has_password ?? true} />

          <ConnectedAccountsPanel hasPassword={user?.has_password ?? true} />

          <Panel
            title="Close your account"
            icon="alertOctagon"
            description="Deactivating is reversible. Deleting removes your personal details permanently."
            className="dangerPanel"
          >
            <div className="accountActions">
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
              <Button variant="danger" onClick={() => setConfirmingDelete(true)}>
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
      </div>
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
        <Button variant="secondary" onClick={form.onSubmit} loading={form.pending}>
          Resend confirmation link
        </Button>
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

  // The link callback redirects back here with ?linked=<provider>.
  const justLinked = query.get("linked");

  if (!providers.length) return null;

  const linkedKeys = new Set((linked || []).map((identity) => identity.provider));
  // Disconnecting the only way in would lock the account out of itself. The
  // server refuses it too; this just avoids offering a button that will fail.
  const canUnlink = hasPassword || linkedKeys.size > 1;

  return (
    <Panel
      title="Connected accounts"
      icon="link"
      description="Sign in with a provider instead of a password."
    >
      {justLinked ? (
        <FormStatus success={`Your ${justLinked} account is connected.`} />
      ) : null}
      {!hasPassword && linkedKeys.size === 1 ? (
        <Callout tone="info" icon="info">
          This is your only way to sign in. Set a password above before
          disconnecting it.
        </Callout>
      ) : null}

      <ul className="providerList">
        {providers.map((provider) => {
          const identity = (linked || []).find((item) => item.provider === provider.key);
          return (
            <li key={provider.key} className="providerList__item">
              <div className="providerList__identity">
                <p className="providerList__name">{provider.display_name}</p>
                <p className="providerList__meta">
                  {identity
                    ? `Connected${identity.email ? ` as ${identity.email}` : ""}`
                    : "Not connected"}
                </p>
              </div>
              {identity ? (
                <Button
                  variant="ghost"
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
                <a
                  className="btn btn--secondary btn--sm"
                  href={`${API_BASE}/api/auth/oauth/${provider.key}/link`}
                >
                  Connect
                </a>
              )}
            </li>
          );
        })}
      </ul>
    </Panel>
  );
}

/**
 * Password settings.
 *
 * An account created through a provider has no password to change, so showing
 * it a three-field change form is asking it to fill in a thing it does not
 * have. It gets a single button instead, and the form only appears once the
 * user has said they want one.
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

  // Every hook above runs unconditionally; only the render branches.
  if (!hasPassword && !creating) {
    return (
      <Panel
        title="Password"
        icon="shield"
        description="You sign in through a connected account. A password is optional."
      >
        <Button variant="secondary" size="sm" onClick={() => setCreating(true)}>
          Create a password
        </Button>
      </Panel>
    );
  }

  return (
    <Panel
      title={hasPassword ? "Password" : "Create a password"}
      icon="shield"
      description={
        hasPassword
          ? "Other devices are signed out when you change it."
          : "Adds a second way into your account, alongside your connected one."
      }
    >
      <form onSubmit={form.onSubmit} noValidate className="accountForm">
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
      </form>
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
      <form onSubmit={form.onSubmit} noValidate>
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
        <div className="accountActions">
          <Button variant="secondary" type="button" onClick={onClose}>
            Cancel
          </Button>
          <Button
            type="submit"
            variant="danger"
            loading={form.pending}
            disabled={confirmText.trim().toUpperCase() !== "DELETE" || !password}
          >
            Delete my account
          </Button>
        </div>
      </form>
    </Modal>
  );
}

/** A short, human description. Never used for anything but display. */
function describeUserAgent(userAgent) {
  if (!userAgent) return "Unknown device";
  const browser =
    /Edg\//.test(userAgent) ? "Edge"
    : /OPR\//.test(userAgent) ? "Opera"
    : /Firefox\//.test(userAgent) ? "Firefox"
    : /Chrome\//.test(userAgent) ? "Chrome"
    : /Safari\//.test(userAgent) ? "Safari"
    : "Browser";
  const platform =
    /iPhone|iPad/.test(userAgent) ? "iOS"
    : /Android/.test(userAgent) ? "Android"
    : /Mac OS X/.test(userAgent) ? "macOS"
    : /Windows/.test(userAgent) ? "Windows"
    : /Linux/.test(userAgent) ? "Linux"
    : "";
  return platform ? `${browser} on ${platform}` : browser;
}
