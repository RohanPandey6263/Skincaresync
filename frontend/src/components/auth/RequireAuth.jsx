/**
 * Client-side route guard.
 *
 * A redirect for the user's benefit, not a security control. Everything it
 * protects is also protected on the server.
 */

import { useEffect } from "react";
import { Spinner } from "../ui/Spinner.jsx";
import { AuthShell } from "./AuthShell.jsx";
import { useAuth } from "../../context/AuthContext.jsx";
import { returnToParam, useRouter } from "../../lib/router.jsx";

export function RequireAuth({ children, requireVerified = false, requireAdmin = false }) {
  const { isLoading, isAuthenticated, isVerified, isAdmin } = useAuth();
  const { navigate } = useRouter();

  useEffect(() => {
    if (isLoading) return;
    if (!isAuthenticated) {
      navigate(`/signin${returnToParam()}`, { replace: true });
      return;
    }
    if (requireVerified && !isVerified) {
      navigate("/verify-email?sent=1", { replace: true });
    }
  }, [isLoading, isAuthenticated, isVerified, requireVerified, navigate]);

  if (isLoading) {
    return (
      <main className="grid min-h-dvh place-items-center bg-paper" id="main">
        <p className="flex items-center gap-3 font-sans text-xs label-caps text-ink" role="status" aria-live="polite">
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
    return <AuthShell number="404" eyebrow="Not found" title="Not found." description="That page does not exist, or you do not have access to it." />;
  }

  return children;
}
