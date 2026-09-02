import { useCallback, useEffect, useRef, useState } from "react";
import { SiteHeader } from "./components/SiteHeader.jsx";
import { SiteFooter } from "./components/SiteFooter.jsx";
import { Hero } from "./components/Hero.jsx";
import { IngredientFinder } from "./components/IngredientFinder.jsx";
import { HowItWorks } from "./components/HowItWorks.jsx";
import { Evidence, LandingDetails } from "./components/LandingDetails.jsx";
import { SkinProfileCard } from "./components/SkinProfileCard.jsx";
import { RoutineBuilder } from "./components/RoutineBuilder.jsx";
import { ResultsPanel } from "./components/ResultsPanel.jsx";
import { ResearchBacklog } from "./components/ResearchBacklog.jsx";
import { ScannerDialog } from "./components/ScannerDialog.jsx";
import { Button } from "./components/ui/Button.jsx";
import { Callout } from "./components/ui/Feedback.jsx";
import { Container } from "./components/ui/Section.jsx";
import { useToast } from "./components/ui/Toaster.jsx";
import { useBarcodeScanner } from "./hooks/useBarcodeScanner.js";
import { useAuth } from "./context/AuthContext.jsx";
import * as api from "./lib/api.js";
import { ROUTINES } from "./lib/constants.js";
import { DEFAULT_TAB, tabFromHash, tabHash } from "./lib/tabs.js";
import { createExampleProducts, createProduct, isReadyForAnalysis } from "./lib/products.js";
import { productLabel } from "./lib/format.js";

export default function App() {
  const { notify } = useToast();
  // The research backlog is an administrative view; the API 404s it for
  // everyone else, so it is not requested or rendered for them.
  const { isAdmin } = useAuth();

  const [skinType, setSkinType] = useState("normal");
  const [concerns, setConcerns] = useState([]);
  const [products, setProducts] = useState(createExampleProducts);
  const [result, setResult] = useState(null);
  const [analyzing, setAnalyzing] = useState(false);
  const [attemptedAnalyze, setAttemptedAnalyze] = useState(false);
  const [gaps, setGaps] = useState([]);
  const [gapsLoading, setGapsLoading] = useState(false);
  const [health, setHealth] = useState({
    status: "checking",
    ingredientCount: null,
    productCount: null,
    interactionCount: null,
  });
  const [busy, setBusy] = useState({});
  const [tab, setTab] = useState(() => tabFromHash(DEFAULT_TAB));

  const readyProducts = {
    am: products.am.filter(isReadyForAnalysis),
    pm: products.pm.filter(isReadyForAnalysis),
  };
  const readyCount = readyProducts.am.length + readyProducts.pm.length;
  const canAnalyze = readyCount >= 2;

  useEffect(() => {
    let active = true;
    api
      .getHealth()
      .then((data) => {
        if (active) {
          setHealth({
            status: "online",
            ingredientCount: data.ingredient_count,
            productCount: data.product_count,
            interactionCount: data.interaction_count,
          });
        }
      })
      .catch(() => {
        if (active) {
          setHealth({
            status: "offline",
            ingredientCount: null,
            productCount: null,
            interactionCount: null,
          });
        }
      });
    return () => {
      active = false;
    };
  }, []);

  // The hash is the single source of truth for which tab is open, so the back
  // button, a pasted link and an in-page anchor all work without extra wiring.
  useEffect(() => {
    const onHashChange = () => setTab((current) => tabFromHash(current));
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, []);

  const selectTab = useCallback((key) => {
    const hash = tabHash(key);
    if (window.location.hash === hash) {
      setTab(key);
      return;
    }
    // Assigning the hash pushes a history entry and fires `hashchange`, which
    // is what actually moves the tab. Setting state here as well would race it.
    window.location.hash = hash;
  }, []);

  // A tab change swaps the whole page, so the jump to the top is immediate.
  useEffect(() => {
    window.scrollTo(0, 0);
  }, [tab]);

  const patchProduct = useCallback((routine, id, patch) => {
    setProducts((current) => ({
      ...current,
      [routine]: current[routine].map((product) =>
        product.id === id
          ? { ...product, ...(typeof patch === "function" ? patch(product) : patch) }
          : product,
      ),
    }));
  }, []);

  const setProductBusy = useCallback((id, value) => {
    setBusy((current) => {
      if (!value) {
        const { [id]: _removed, ...rest } = current;
        return rest;
      }
      return { ...current, [id]: value };
    });
  }, []);

  const findProduct = useCallback(
    (routine, id) => products[routine].find((product) => product.id === id),
    [products],
  );

  function handleFieldChange(routine, id, field, value) {
    const patch = { [field]: value };
    if (field === "brand" || field === "name") {
      patch.matchScore = null;
      patch.isExample = false;
    }
    patchProduct(routine, id, patch);
  }

  function handleAdd(routine) {
    setProducts((current) => ({
      ...current,
      [routine]: [...current[routine], createProduct()],
    }));
  }

  function handleRemove(routine, id) {
    const removed = findProduct(routine, id);
    setProducts((current) => ({
      ...current,
      [routine]: current[routine].filter((product) => product.id !== id),
    }));
    notify({
      tone: "info",
      title: "Product removed",
      description: productLabel(removed, "The product") + " is no longer in the routine.",
    });
  }

  function handleClearAll() {
    setProducts({ am: [createProduct()], pm: [createProduct()] });
    setResult(null);
    setAttemptedAnalyze(false);
    notify({ tone: "info", title: "Routines cleared", description: "Both routines were reset." });
  }

  function applyLookupResult(routine, id, match) {
    const score = typeof match.similarity_score === "number" ? match.similarity_score : null;

    patchProduct(routine, id, (existing) => ({
      brand: (existing.isExample ? "" : existing.brand.trim()) || match.brand || "",
      name: match.name || existing.name || "",
      code: match.code || existing.code || "",
      raw_ingredient_list: match.raw_ingredient_list,
      image_url: match.image_url ?? null,
      product_url: match.product_url ?? null,
      matchScore: score,
      isExample: false,
      lookupState: "success",
      // `score` is a number or null, and 0 is a real score -- a truthiness test
      // here reported a genuine 0% match as an unqualified success.
      lookupMessage:
        score === null
          ? "Ingredient list loaded."
          : `Matched ${productLabel(match, "this product")} at ${score}% confidence.`,
    }));

    notify({
      tone: "ok",
      title: "Ingredient list loaded",
      description: productLabel(match, "Product") + " is ready to analyze.",
    });
  }

  const lookupByCode = useCallback(
    async (routine, id, explicitCode) => {
      const product = products[routine].find((entry) => entry.id === id);
      const code = (explicitCode ?? product?.code ?? "").trim();
      if (!code) {
        patchProduct(routine, id, {
          lookupState: "error",
          lookupMessage: "Enter or scan a product code first.",
        });
        return;
      }

      setProductBusy(id, "code");
      patchProduct(routine, id, { lookupState: "loading", lookupMessage: "Looking up code…" });
      try {
        applyLookupResult(routine, id, await api.lookupProductByCode(code));
      } catch (error) {
        patchProduct(routine, id, { lookupState: "error", lookupMessage: error.message });
        notify({ tone: "danger", title: "Code lookup failed", description: error.message });
      } finally {
        setProductBusy(id, false);
      }
    },
    // applyLookupResult/notify are stable enough for this call site; products is
    // the value that must stay fresh for the scanner callback.
    [products, patchProduct, setProductBusy], // eslint-disable-line react-hooks/exhaustive-deps
  );

  async function searchProduct(routine, id) {
    const product = findProduct(routine, id);
    if (!product?.brand?.trim() && !product?.name?.trim()) {
      patchProduct(routine, id, {
        lookupState: "error",
        lookupMessage: "Add a brand or product name to search.",
      });
      return;
    }

    setProductBusy(id, "search");
    patchProduct(routine, id, {
      lookupState: "loading",
      lookupMessage: "Searching product databases…",
    });

    try {
      const matches = await api.searchProducts({ brand: product.brand, name: product.name });
      const best = matches[0];

      // The confidence floor lives in the API, which now returns only matches
      // above it. The client used to keep its own copy of the threshold, so the
      // two could drift apart silently.
      if (!best) {
        throw new api.ApiError(
          "No confident match found. Try the full product name, or use the barcode instead.",
        );
      }

      applyLookupResult(routine, id, best);
    } catch (error) {
      patchProduct(routine, id, { lookupState: "error", lookupMessage: error.message });
      notify({ tone: "danger", title: "Product not found", description: error.message });
    } finally {
      setProductBusy(id, false);
    }
  }

  const scanner = useBarcodeScanner({
    onDetect: (target, code) => {
      if (!target) return;
      patchProduct(target.routine, target.id, { code });
      lookupByCode(target.routine, target.id, code);
    },
    onError: (message) => notify({ tone: "warn", title: "Scanner unavailable", description: message }),
  });

  async function analyze() {
    if (!canAnalyze) {
      setAttemptedAnalyze(true);
      notify({
        tone: "warn",
        title: "Two products needed",
        description: "Load ingredient lists for at least two products before analyzing.",
      });
      return;
    }

    setAnalyzing(true);
    setAttemptedAnalyze(false);
    try {
      const data = await api.analyzeRoutine({
        skinProfile: { skinType, concerns },
        amProducts: readyProducts.am,
        pmProducts: readyProducts.pm,
      });
      setResult(data);

      const { status } = data.overall_score;
      notify({
        tone: status === "conflict" ? "danger" : status === "caution" ? "warn" : "ok",
        title:
          status === "conflict"
            ? "Conflicts detected"
            : status === "caution"
              ? "Cautions to review"
              : "No conflicts detected",
        description: `${data.conflicts.length} conflicts, ${data.cautions.length} cautions, ${data.synergies.length} synergies.`,
      });

      // The report is its own tab now, so a finished analysis has to take the
      // user there -- otherwise the result lands on a screen they cannot see.
      selectTab("report");
      if (isAdmin) refreshGaps();
    } catch (error) {
      notify({ tone: "danger", title: "Analysis failed", description: error.message });
    } finally {
      setAnalyzing(false);
    }
  }

  async function refreshGaps() {
    setGapsLoading(true);
    try {
      setGaps(await api.getGaps());
    } catch (error) {
      notify({ tone: "danger", title: "Could not load backlog", description: error.message });
    } finally {
      setGapsLoading(false);
    }
  }

  // A non-admin can still arrive at #backlog by hand; there is nothing behind it
  // for them, so fall back rather than render an empty admin view.
  const activeTab = tab === "backlog" && !isAdmin ? DEFAULT_TAB : tab;


  return (
    <>
      <a
        className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-50 focus:bg-ink focus:px-4 focus:py-3 focus:font-sans focus:text-xs focus:text-paper label-caps"
        href="#main"
      >
        Skip to content
      </a>
      <SiteHeader
        healthStatus={health.status}
        ingredientCount={health.ingredientCount}
        activeTab={activeTab}
        onSelectTab={selectTab}
      />

      <main className="flex-1 focus:outline-none" id="main" tabIndex={-1}>
        <Container className="flex flex-col">
          {health.status === "offline" ? (
            <div className="pt-8">
              <Callout tone="danger" title="Backend not reachable">
                Start the API with <code className="font-mono">uvicorn skincaresync.api:app --reload</code> so lookups and
                analysis can run.
              </Callout>
            </div>
          ) : null}

          {activeTab === "home" ? (
            <div className="flex flex-col">
              <Hero
                ingredientCount={health.ingredientCount}
                productCount={health.productCount}
                interactionCount={health.interactionCount}
                onStart={() => selectTab("analyze")}
              />
              <HowItWorks />
              <LandingDetails catalogStats={health} onStart={() => selectTab("analyze")} />
              <Evidence />
            </div>
          ) : null}

          {activeTab === "analyze" ? (
            <div className="flex flex-col gap-8 py-8 md:gap-10 md:py-12">
              <SkinProfileCard
                skinType={skinType}
                concerns={concerns}
                onSkinTypeChange={setSkinType}
                onToggleConcern={(concern) =>
                  setConcerns((current) =>
                    current.includes(concern) ? current.filter((item) => item !== concern) : [...current, concern],
                  )
                }
              />

              {[ROUTINES.am, ROUTINES.pm].map((routine) => (
                <RoutineBuilder
                  key={routine.key}
                  routine={routine}
                  products={products[routine.key]}
                  busy={busy}
                  missingRequired={attemptedAnalyze}
                  scanSupported={scanner.supported}
                  onAdd={() => handleAdd(routine.key)}
                  onRemove={(id) => handleRemove(routine.key, id)}
                  onFieldChange={(id, field, value) => handleFieldChange(routine.key, id, field, value)}
                  onLookupCode={(id) => lookupByCode(routine.key, id)}
                  onSearch={(id) => searchProduct(routine.key, id)}
                  onScan={(id) => scanner.start({ routine: routine.key, id })}
                />
              ))}

              {/* The action bar is a black band pinned to the bottom of the
                  viewport while the builder scrolls. Red is the one CTA. */}
              <div className="sticky bottom-0 z-20 border-t-4 border-ink bg-ink px-6 py-4 text-paper md:px-8">
                <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
                  <div className="flex items-baseline gap-4">
                    <p className="font-sans text-3xl font-black leading-none tracking-tighter">
                      {String(readyCount).padStart(2, "0")}
                    </p>
                    <div className="flex flex-col gap-0.5">
                      <p className="font-sans text-xs label-caps">product{readyCount === 1 ? "" : "s"} ready</p>
                      <p className="hidden font-sans text-xs text-paper/60 sm:block">
                        {canAnalyze ? "Analysis covers each routine and the AM/PM overlap." : "At least two products need ingredient lists."}
                      </p>
                    </div>
                  </div>
                  {/* On a phone the two quiet actions share a row and the CTA takes the full width. */}
                  <div className="grid grid-cols-2 gap-2 sm:flex sm:flex-wrap sm:items-center sm:gap-3">
                    {result ? (
                      <Button variant="inverse" size="sm" onClick={() => selectTab("report")} disabled={analyzing} className="sm:h-11 sm:px-6 sm:text-xs">
                        Last report
                      </Button>
                    ) : null}
                    <Button variant="inverse" size="sm" onClick={handleClearAll} disabled={analyzing} className={`sm:h-11 sm:px-6 sm:text-xs ${result ? "" : "col-span-2"}`}>
                      Clear all
                    </Button>
                    <Button
                      variant="accent"
                      size="lg"
                      iconAfter="arrowRight"
                      onClick={analyze}
                      loading={analyzing}
                      disabled={!canAnalyze && attemptedAnalyze}
                      className="col-span-2"
                    >
                      {analyzing ? "Analyzing" : "Analyze routine"}
                    </Button>
                  </div>
                </div>
              </div>
            </div>
          ) : null}

          {activeTab === "report" ? (
            <div className="flex flex-col py-8 md:py-12">
              <ResultsPanel
                result={result}
                loading={analyzing}
                skinType={skinType}
                concerns={concerns}
                onGoToBuilder={() => selectTab("analyze")}
              />
            </div>
          ) : null}

          {activeTab === "catalog" ? (
            <div className="flex flex-col py-8 md:py-12">
              <IngredientFinder />
            </div>
          ) : null}

          {activeTab === "backlog" && isAdmin ? (
            <div className="flex flex-col py-8 md:py-12">
              <ResearchBacklog gaps={gaps} loading={gapsLoading} onRefresh={refreshGaps} />
            </div>
          ) : null}
        </Container>
      </main>

      <SiteFooter />

      <ScannerDialog open={scanner.isOpen} status={scanner.status} videoRef={scanner.videoRef} onClose={scanner.stop} />
    </>
  );
}
