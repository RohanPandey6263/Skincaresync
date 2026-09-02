/**
 * Route table.
 *
 * Flat and explicit: six auth paths plus the analyser. `App` keeps its own
 * state across navigations because it is only unmounted when the user leaves
 * the analyser, which is the behaviour we want -- a half-built routine survives
 * a trip to the account page.
 */

import App from "./App.jsx";
import { AccountSecurityPage } from "./components/auth/AccountSecurityPage.jsx";
import { ForgotPasswordPage, ResetPasswordPage } from "./components/auth/PasswordResetPages.jsx";
import { RegisterPage } from "./components/auth/RegisterPage.jsx";
import { RequireAuth } from "./components/auth/RequireAuth.jsx";
import { SignInPage } from "./components/auth/SignInPage.jsx";
import { VerifyEmailPage } from "./components/auth/VerifyEmailPage.jsx";
import { AuthShell } from "./components/auth/AuthShell.jsx";
import { ButtonLink } from "./components/ui/Button.jsx";
import { useRouter } from "./lib/router.jsx";

const ROUTES = {
  "/": () => <App />,
  "/signin": () => <SignInPage />,
  "/register": () => <RegisterPage />,
  "/verify-email": () => <VerifyEmailPage />,
  "/forgot-password": () => <ForgotPasswordPage />,
  "/reset-password": () => <ResetPasswordPage />,
  "/account/security": () => (
    <RequireAuth>
      <AccountSecurityPage />
    </RequireAuth>
  ),
};

export function Routes() {
  const { path } = useRouter();
  // Trailing slashes are equivalent, so /signin/ is not a 404.
  const normalized = path.length > 1 ? path.replace(/\/+$/, "") : path;
  const render = ROUTES[normalized];
  return render ? render() : <NotFound />;
}

function NotFound() {
  return (
    <AuthShell
      number="404"
      title="Page not found"
      description="That page does not exist. It may have moved, or the link may be incomplete."
    >
      <ButtonLink to="/" variant="primary" size="lg" block>
        Back to the analyser
      </ButtonLink>
    </AuthShell>
  );
}
