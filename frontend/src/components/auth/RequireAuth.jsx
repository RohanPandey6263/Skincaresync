/**
 * Client-side route guard.
 *
 * This is a redirect for the user's benefit, not a security control. Everything
 * it protects is also protected on the server, so bypassing this in devtools
 * gets you a screen whose API calls all return 401.
 */

import { useEffect } from "react";
import { Spinner } from "../ui/Spinner.jsx";
import { useAuth } from "../../context/AuthContext.jsx";
import { returnToParam, useRouter } from "../../lib/router.jsx";

export function RequireAuth({ children, requireVerified = false, requireAdmin = false }) {
  const { isLoading, isAuthenticated, isVerified, isAdmin } = useAuth();
  const { navigate } = useRouter();

  useEffect(() => {
    if (isLoading) return;
    if (!isAuthenticated) {
      // Carries the intended destination so the user lands where they meant to.
      navigate(`/signin${returnToParam()}`, { replace: true });
      return;
    }
    if (requireVerified && !isVerified) {
      navigate("/verify-email?sent=1", { replace: true });
    }
  }, [isLoading, isAuthenticated, isVerified, requireVerified, navigate]);

  if (isLoading) {
    return (
      <main className="authPage" id="main">
        <p className="authCard__pending" role="status" aria-live="polite">
          <Spinner size={18} />
          Checking your session…
        </p>
      </main>
    );
  }

  if (!isAuthenticated) return null;
  if (requireVerified && !isVerified) return null;

  // Admin-only screens render nothing rather than an explanation, matching the
  // server, which 404s rather than confirming the surface exists.
  if (requireAdmin && !isAdmin) {
    return (
      <main className="authPage" id="main">
        <div className="authCard">
          <h1 className="authCard__title">Not found</h1>
          <p className="authCard__description">
            That page does not exist, or you do not have access to it.
          </p>
        </div>
      </main>
    );
  }

  return children;
}
