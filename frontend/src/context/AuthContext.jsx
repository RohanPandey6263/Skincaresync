/**
 * Session state for the whole app.
 *
 * The user object here is a convenience for rendering, never a security
 * boundary. Every protected route re-checks on the server, so tampering with
 * this state in devtools reveals nothing and grants nothing.
 */

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { authApi } from "../lib/authApi.js";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  // "loading" until the first session check resolves, so protected screens do
  // not flash a sign-in prompt at a user who is in fact signed in.
  const [status, setStatus] = useState("loading");

  const refresh = useCallback(async () => {
    try {
      const payload = await authApi.session();
      setUser(payload?.user ?? null);
      setStatus("ready");
      return payload?.user ?? null;
    } catch {
      // A failed bootstrap means signed out, not broken. The app still works
      // for anonymous visitors.
      setUser(null);
      setStatus("ready");
      return null;
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const signIn = useCallback(async (credentials) => {
    const payload = await authApi.login(credentials);
    setUser(payload.user);
    setStatus("ready");
    return payload;
  }, []);

  const signOut = useCallback(async () => {
    try {
      await authApi.logout();
    } finally {
      // Clear locally even if the call failed; the cookie may already be gone.
      setUser(null);
    }
  }, []);

  const signOutEverywhere = useCallback(async () => {
    try {
      await authApi.logoutAll();
    } finally {
      setUser(null);
    }
  }, []);

  const value = useMemo(
    () => ({
      user,
      status,
      isLoading: status === "loading",
      isAuthenticated: Boolean(user),
      isAdmin: user?.role === "admin",
      isVerified: Boolean(user?.email_verified),
      refresh,
      signIn,
      signOut,
      signOutEverywhere,
      setUser,
    }),
    [user, status, refresh, signIn, signOut, signOutEverywhere],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) throw new Error("useAuth must be used inside an AuthProvider");
  return context;
}
