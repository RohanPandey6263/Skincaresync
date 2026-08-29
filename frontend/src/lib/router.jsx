/**
 * A minimal history router.
 *
 * The app has exactly two runtime dependencies -- react and react-dom -- and the
 * routing it needs is six flat paths with no nesting, no loaders and no code
 * splitting. Adding react-router for that would be a larger dependency than the
 * feature. If routing grows nested layouts or data loading, replace this; the
 * surface below is deliberately a subset of react-router's so that swap is
 * mechanical.
 *
 * Real paths rather than hashes, because verification and reset links have to
 * survive being pasted into a mail client and opened cold.
 */

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";

const RouterContext = createContext(null);

function currentLocation() {
  return {
    path: window.location.pathname,
    search: window.location.search,
    hash: window.location.hash,
  };
}

export function RouterProvider({ children }) {
  const [location, setLocation] = useState(currentLocation);

  useEffect(() => {
    const onPopState = () => setLocation(currentLocation());
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, []);

  const navigate = useCallback((to, { replace = false } = {}) => {
    // Only same-site paths are ever pushed. A caller that hands us an absolute
    // URL is either confused or hostile, and either way this is not the place
    // to leave the site from.
    const target = typeof to === "string" && to.startsWith("/") && !to.startsWith("//") ? to : "/";
    if (target === window.location.pathname + window.location.search) return;
    window.history[replace ? "replaceState" : "pushState"]({}, "", target);
    setLocation(currentLocation());
    window.scrollTo(0, 0);
  }, []);

  const value = useMemo(
    () => ({
      ...location,
      navigate,
      query: new URLSearchParams(location.search),
    }),
    [location, navigate],
  );

  return <RouterContext.Provider value={value}>{children}</RouterContext.Provider>;
}

export function useRouter() {
  const context = useContext(RouterContext);
  if (!context) throw new Error("useRouter must be used inside a RouterProvider");
  return context;
}

/** An anchor that navigates without a full page load, but is still a real link. */
export function Link({ to, children, className, ...rest }) {
  const { navigate } = useRouter();

  return (
    <a
      href={to}
      className={className}
      onClick={(event) => {
        // Let the browser handle modified clicks so "open in new tab" works.
        if (event.defaultPrevented || event.button !== 0) return;
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        event.preventDefault();
        navigate(to);
      }}
      {...rest}
    >
      {children}
    </a>
  );
}

/**
 * The path the user was trying to reach, encoded for a `next` parameter.
 * Always site-relative; the server validates it again before using it.
 */
export function returnToParam() {
  const { pathname, search } = window.location;
  const target = `${pathname}${search}`;
  return target === "/" ? "" : `?next=${encodeURIComponent(target)}`;
}
