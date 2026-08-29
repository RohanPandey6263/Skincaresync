/** Account and security settings: password, devices, activity, and closing the account. */

import { useCallback, useEffect, useState } from "react";
import { Panel } from "../ui/Panel.jsx";
import { Button } from "../ui/Button.jsx";
import { Badge } from "../ui/Badge.jsx";
import { Callout, EmptyState } from "../ui/Feedback.jsx";
import { TextInput } from "../ui/Field.jsx";
import { Modal } from "../ui/Modal.jsx";
import { Spinner } from "../ui/Spinner.jsx";
import { FormStatus, PasswordInput, SubmitButton, useAuthForm } from "./AuthShell.jsx";
import { authApi } from "../../lib/authApi.js";
import { API_BASE } from "../../lib/api.js";
import { useAuth } from "../../context/AuthContext.jsx";
import { useRouter } from "../../lib/router.jsx";
import { useToast } from "../ui/Toaster.jsx";
import { formatRelativeDate } from "../../lib/format.js";

const MIN_PASSWORD_LENGTH = 12;

const EVENT_LABELS = {
  "register.success": "Account created",
  "register.duplicate": "Registration attempted for this address",
  "email.verified": "Email confirmed",
  "verification.resent": "Verification link resent",
  "login.success": "Signed in",
  "login.failure": "Failed sign-in attempt",
  "login.blocked": "Sign-in blocked",
  "login.locked": "Account temporarily locked",
  logout: "Signed out",
  logout_all: "Signed out of all devices",
  "password.changed": "Password changed",
  "password.reset": "Password reset",
  "password.change_failed": "Failed password change",
  "password_reset.requested": "Password reset requested",
  "session.revoked": "Device signed out",
  "role.changed": "Role changed",
  "oauth.login": "Signed in with a connected account",
  "oauth.linked": "Connected account linked",
  "oauth.unlinked": "Connected account disconnected",
  "oauth.registered": "Account created with a connected account",
  "oauth.link_refused": "Connection refused (unverified email)",
  "oauth.failed": "Connected sign-in failed",
  "password.set": "Password set",
  "account.deactivated": "Account deactivated",
  "account.deleted": "Account deleted",
};

export function AccountSecurityPage() {
  const { user, refresh, signOutEverywhere } = useAuth();
  const { navigate } = useRouter();
  const { notify } = useToast();

  const [sessions, setSessions] = useState(null);
  const [events, setEvents] = useState(null);
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  const loadSessions = useCallback(async () => {
    try {
      setSessions(await authApi.listSessions());
    } catch {
      setSessions([]);
    }
  }, []);

  useEffect(() => {
    loadSessions();
    authApi.events().then(setEvents).catch(() => setEvents([]));
  }, [loadSessions]);

  return (
    <main className="page accountPage" id="main" tabIndex={-1}>
      <div className="container">
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

        {!user?.email_verified ? <UnverifiedNotice email={user?.email} /> : null}

        <ChangePasswordPanel hasPassword={user?.has_password ?? true} />

        <ConnectedAccountsPanel hasPassword={user?.has_password ?? true} />

        <SessionsPanel
          sessions={sessions}
          onReload={loadSessions}
          onSignOutEverywhere={async () => {
            await signOutEverywhere();
            notify({ tone: "ok", title: "Signed out everywhere" });
            navigate("/signin", { replace: true });
          }}
        />

        <ActivityPanel events={events} />

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

      <ul className="sessionList">
        {providers.map((provider) => {
          const identity = (linked || []).find((item) => item.provider === provider.key);
          return (
            <li key={provider.key} className="sessionList__item">
              <div>
                <p className="sessionList__title">{provider.display_name}</p>
                <p className="sessionList__meta">
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

function ChangePasswordPanel({ hasPassword }) {
  const { notify } = useToast();
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

  return (
    <Panel
      title={hasPassword ? "Password" : "Set a password"}
      icon="shield"
      description={
        hasPassword
          ? "Other devices are signed out when you change it."
          : "Your account signs in through a connected provider. Add a password as a second way in."
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
          {hasPassword ? "Update password" : "Set password"}
        </SubmitButton>
      </form>
    </Panel>
  );
}

function SessionsPanel({ sessions, onReload, onSignOutEverywhere }) {
  const { notify } = useToast();
  const [busyId, setBusyId] = useState(null);

  if (sessions === null) {
    return (
      <Panel title="Signed-in devices" icon="refresh">
        <p className="authCard__pending" role="status">
          <Spinner size={15} /> Loading your devices…
        </p>
      </Panel>
    );
  }

  return (
    <Panel
      title="Signed-in devices"
      icon="refresh"
      description="Sessions currently able to use your account."
      actions={
        sessions.length > 1 ? (
          <Button variant="quiet" onClick={onSignOutEverywhere}>
            Sign out everywhere
          </Button>
        ) : null
      }
    >
      {sessions.length === 0 ? (
        <EmptyState icon="info" compact title="No active sessions" />
      ) : (
        <ul className="sessionList">
          {sessions.map((session) => (
            <li key={session.session_id} className="sessionList__item">
              <div>
                <p className="sessionList__title">
                  {describeUserAgent(session.user_agent)}
                  {session.current ? <Badge tone="ok" size="sm">This device</Badge> : null}
                </p>
                <p className="sessionList__meta">
                  {session.ip_address || "Unknown location"} · last active{" "}
                  {formatRelativeDate(session.last_seen_at) || "recently"}
                </p>
              </div>
              {!session.current ? (
                <Button
                  variant="ghost"
                  size="sm"
                  loading={busyId === session.session_id}
                  onClick={async () => {
                    setBusyId(session.session_id);
                    try {
                      await authApi.revokeSession(session.session_id);
                      notify({ tone: "ok", title: "Device signed out" });
                      await onReload();
                    } finally {
                      setBusyId(null);
                    }
                  }}
                >
                  Sign out
                </Button>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </Panel>
  );
}

function ActivityPanel({ events }) {
  if (events === null) {
    return (
      <Panel title="Recent security activity" icon="database">
        <p className="authCard__pending" role="status">
          <Spinner size={15} /> Loading activity…
        </p>
      </Panel>
    );
  }

  return (
    <Panel
      title="Recent security activity"
      icon="database"
      description="Sign-ins, password changes and other account events."
    >
      {events.length === 0 ? (
        <EmptyState icon="database" compact title="Nothing recorded yet" />
      ) : (
        <div className="tableWrap">
          <table className="table">
            <caption className="visuallyHidden">Recent account security events</caption>
            <thead>
              <tr>
                <th scope="col">Event</th>
                <th scope="col">When</th>
                <th scope="col">Address</th>
              </tr>
            </thead>
            <tbody>
              {events.map((event, index) => (
                <tr key={`${event.event_type}-${event.created_at}-${index}`}>
                  <td>{EVENT_LABELS[event.event_type] || event.event_type}</td>
                  <td className="table__muted">{formatRelativeDate(event.created_at)}</td>
                  <td className="table__muted">{event.ip_address || "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
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
