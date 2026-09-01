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
import { useEffect } from "react";
import { Link, useRouter } from "./lib/router.jsx";
import { startSmoothScroll } from "./lib/smoothScroll.js";

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

  // Site-wide: the account and auth pages scroll like the rest of the app.
  // Started here rather than in `App` so it is not torn down and rebuilt on
  // every navigation away from the analyser.
  useEffect(() => startSmoothScroll(), []);
  // Trailing slashes are equivalent, so /signin/ is not a 404.
  const normalized = path.length > 1 ? path.replace(/\/+$/, "") : path;
  const render = ROUTES[normalized];
  return render ? render() : <NotFound />;
}

function NotFound() {
  return (
    <main className="authPage" id="main">
      <div className="authCard">
        <h1 className="authCard__title">Page not found</h1>
        <p className="authCard__description">
          That page does not exist. It may have moved, or the link may be incomplete.
        </p>
        <Link to="/" className="btn btn--primary btn--lg btn--block">
          Back to the analyser
        </Link>
      </div>
    </main>
  );
}
