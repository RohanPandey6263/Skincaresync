import { useEffect, useId, useRef, useState } from "react";
import { Panel } from "./ui/Panel.jsx";
import { Button } from "./ui/Button.jsx";
import { Icon } from "./ui/Icon.jsx";
import { CONTROL, CONTROL_BOXED } from "./ui/Field.jsx";
import { EmptyState, SkeletonCard } from "./ui/Feedback.jsx";
import { IngredientCard } from "./IngredientCard.jsx";
import { IngredientDetail } from "./IngredientDetail.jsx";
import { useDebouncedValue } from "../hooks/useDebouncedValue.js";
import * as api from "../lib/api.js";
import { formatFunction, pluralize } from "../lib/format.js";

const LETTERS = ["#", ..."ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")];
const PAGE_SIZE = 24;
const TOP_FUNCTIONS = 10;

/** A rectangular toggle. Active is black; hover is the red signal. */
function FilterChip({ active, className = "", children, ...rest }) {
  return (
    <button
      type="button"
      className={`inline-flex h-10 items-center gap-2 border-2 border-black px-3 font-sans text-2xs label-caps transition-colors duration-150 ease-linear
                  hover:border-accent hover:bg-accent hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2
                  ${active ? "bg-black text-white" : "bg-white text-black"} ${className}`}
      aria-pressed={active}
      {...rest}
    >
      {children}
    </button>
  );
}

export function IngredientFinder() {
  const searchId = useId();
  const listId = useId();
  const [query, setQuery] = useState("");
  const [functionFilter, setFunctionFilter] = useState("");
  const [letter, setLetter] = useState("");
  const [engineOnly, setEngineOnly] = useState(false);
  const [restrictedOnly, setRestrictedOnly] = useState(false);
  const [facets, setFacets] = useState(null);
  const [results, setResults] = useState({ items: [], total: 0, has_more: false });
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState("");
  // Kept apart from `error`: a failed "load more" must not blank the results.
  const [loadMoreError, setLoadMoreError] = useState("");
  const [suggestions, setSuggestions] = useState([]);
  const [suggestOpen, setSuggestOpen] = useState(false);
  const [activeSuggest, setActiveSuggest] = useState(-1);
  const [detailId, setDetailId] = useState(null);
  const [detail, setDetail] = useState(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState("");

  const debouncedQuery = useDebouncedValue(query, 220);
  const suggestQuery = useDebouncedValue(query.trim(), 160);
  const requestRef = useRef(0);
  const searchRef = useRef(null);

  useEffect(() => {
    let active = true;
    api
      .getIngredientFacets()
      .then((data) => {
        if (active) setFacets(data);
      })
      .catch(() => {
        /* facets are optional chrome; search still works */
      });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    const requestId = ++requestRef.current;
    setLoading(true);
    setError("");

    api
      .searchIngredients({
        query: debouncedQuery,
        functions: functionFilter ? [functionFilter] : [],
        letter: letter || undefined,
        onlyWithInteractions: engineOnly,
        onlyRestricted: restrictedOnly,
        limit: PAGE_SIZE,
        offset: 0,
        signal: controller.signal,
      })
      .then((data) => {
        if (requestId !== requestRef.current) return;
        setResults(data);
      })
      .catch((err) => {
        if (err.name === "AbortError") return;
        setError(err.message);
        setResults({ items: [], total: 0, has_more: false });
      })
      .finally(() => {
        if (requestId === requestRef.current) setLoading(false);
      });

    return () => controller.abort();
  }, [debouncedQuery, functionFilter, letter, engineOnly, restrictedOnly]);

  useEffect(() => {
    if (suggestQuery.length < 2) {
      setSuggestions([]);
      return undefined;
    }
    const controller = new AbortController();
    api
      .suggestIngredients(suggestQuery, controller.signal)
      .then((items) => {
        setSuggestions(items);
        setActiveSuggest(-1);
      })
      .catch(() => {
        /* keep last suggestions */
      });
    return () => controller.abort();
  }, [suggestQuery]);

  useEffect(() => {
    if (!detailId) {
      setDetail(null);
      setDetailError("");
      return undefined;
    }
    let active = true;
    setDetailLoading(true);
    setDetailError("");
    api
      .getIngredient(detailId)
      .then((data) => {
        if (active) setDetail(data);
      })
      .catch((err) => {
        if (active) setDetailError(err.message);
      })
      .finally(() => {
        if (active) setDetailLoading(false);
      });
    return () => {
      active = false;
    };
  }, [detailId]);

  async function loadMore() {
    // The page being requested belongs to the filter state as it is right now.
    const requestId = requestRef.current;
    setLoadingMore(true);
    setLoadMoreError("");
    try {
      const data = await api.searchIngredients({
        query: debouncedQuery,
        functions: functionFilter ? [functionFilter] : [],
        letter: letter || undefined,
        onlyWithInteractions: engineOnly,
        onlyRestricted: restrictedOnly,
        limit: PAGE_SIZE,
        offset: results.items.length,
      });
      if (requestId !== requestRef.current) return;
      setResults((current) => ({ ...data, items: [...current.items, ...data.items] }));
    } catch (err) {
      if (err.name === "AbortError" || requestId !== requestRef.current) return;
      setLoadMoreError(err.message);
    } finally {
      if (requestId === requestRef.current) setLoadingMore(false);
    }
  }

  function applySuggestion(item) {
    setQuery(item.display_name || item.inci_name);
    setSuggestOpen(false);
    setDetailId(item.id);
  }

  function onSearchKeyDown(event) {
    if (!suggestOpen || !suggestions.length) return;
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setActiveSuggest((current) => (current + 1) % suggestions.length);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setActiveSuggest((current) => (current - 1 + suggestions.length) % suggestions.length);
    } else if (event.key === "Enter" && activeSuggest >= 0) {
      event.preventDefault();
      applySuggestion(suggestions[activeSuggest]);
    } else if (event.key === "Escape") {
      setSuggestOpen(false);
    }
  }

  const topFunctions = (facets?.functions || []).slice(0, TOP_FUNCTIONS);
  const moreFunctions = (facets?.functions || []).slice(TOP_FUNCTIONS);
  const stats = facets?.stats;
  const hasFilters = Boolean(query || functionFilter || letter || engineOnly || restrictedOnly);

  return (
    <Panel
      number="01"
      eyebrow="Catalog"
      title="Ingredient catalog"
      description={
        stats
          ? `${stats.total.toLocaleString()} INCI names from EU CosIng via Open Beauty Facts, plus ${stats.curated} curated engine entries.`
          : "Search official INCI names, synonyms, and CosIng functions."
      }
    >
      <div className="flex flex-col gap-8">
        <div className="relative">
          <label className="sr-only" htmlFor={searchId}>
            Search ingredients
          </label>
          <Icon name="search" size={20} strokeWidth={2.5} className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-black" />
          <input
            id={searchId}
            ref={searchRef}
            className={`${CONTROL_BOXED} h-14 pl-12 pr-14 text-lg md:h-16`}
            value={query}
            placeholder="Search INCI, synonym, or CAS"
            autoComplete="off"
            role="combobox"
            aria-autocomplete="list"
            aria-expanded={suggestOpen && suggestions.length > 0}
            aria-controls={listId}
            aria-activedescendant={activeSuggest >= 0 ? `${listId}-${suggestions[activeSuggest]?.id}` : undefined}
            onChange={(event) => {
              setQuery(event.target.value);
              setSuggestOpen(true);
            }}
            onFocus={() => setSuggestOpen(true)}
            onBlur={() => {
              window.setTimeout(() => setSuggestOpen(false), 120);
            }}
            onKeyDown={onSearchKeyDown}
          />
          {query ? (
            <button
              type="button"
              className="absolute right-2 top-1/2 grid h-10 w-10 -translate-y-1/2 place-items-center text-black transition-colors duration-150 hover:bg-black hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
              aria-label="Clear search"
              onClick={() => {
                setQuery("");
                searchRef.current?.focus();
              }}
            >
              <Icon name="close" size={16} strokeWidth={2.5} />
            </button>
          ) : null}

          {suggestOpen && suggestions.length > 0 ? (
            <ul className="absolute left-0 right-0 top-full z-20 -mt-0.5 flex flex-col border-4 border-black bg-white" id={listId} role="listbox">
              {suggestions.map((item, index) => (
                <li key={item.id} role="presentation" className="border-b-2 border-black last:border-b-0">
                  <button
                    type="button"
                    id={`${listId}-${item.id}`}
                    role="option"
                    aria-selected={index === activeSuggest}
                    className={`flex w-full items-center justify-between gap-4 px-4 py-3 text-left font-sans text-sm transition-colors duration-150 ${
                      index === activeSuggest ? "bg-black text-white" : "text-black hover:bg-black hover:text-white"
                    }`}
                    onMouseDown={(event) => event.preventDefault()}
                    onClick={() => applySuggestion(item)}
                  >
                    <span className="font-bold">{item.display_name}</span>
                    <span className="text-2xs label-caps opacity-70">
                      {item.functions?.[0] ? formatFunction(item.functions[0]) : item.category || "INCI"}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
        </div>

        <div className="flex flex-col gap-4" aria-label="Catalog filters">
          <div className="flex flex-wrap gap-2">
            <FilterChip active={!functionFilter} onClick={() => setFunctionFilter("")}>
              All functions
            </FilterChip>
            {topFunctions.map((item) => (
              <FilterChip
                key={item.value}
                active={functionFilter === item.value}
                onClick={() => setFunctionFilter((current) => (current === item.value ? "" : item.value))}
              >
                {formatFunction(item.value)}
                <span className="opacity-60">{item.count.toLocaleString()}</span>
              </FilterChip>
            ))}
            {moreFunctions.length ? (
              <label className="relative inline-flex h-10 w-56 items-center border-2 border-black bg-white">
                <span className="sr-only">More functions</span>
                <select
                  className={`${CONTROL} h-full cursor-pointer appearance-none border-0 px-3 pr-9 text-2xs label-caps`}
                  value={moreFunctions.some((item) => item.value === functionFilter) ? functionFilter : ""}
                  onChange={(event) => setFunctionFilter(event.target.value)}
                >
                  <option value="">More functions</option>
                  {moreFunctions.map((item) => (
                    <option key={item.value} value={item.value}>
                      {formatFunction(item.value)} ({item.count})
                    </option>
                  ))}
                </select>
                <Icon name="chevronDown" size={14} strokeWidth={2.5} className="pointer-events-none absolute right-3 text-black" />
              </label>
            ) : null}
          </div>

          <div className="flex flex-wrap gap-2">
            <FilterChip active={engineOnly} onClick={() => setEngineOnly((value) => !value)}>
              In compatibility engine
            </FilterChip>
            <FilterChip active={restrictedOnly} onClick={() => setRestrictedOnly((value) => !value)}>
              Restricted
            </FilterChip>
          </div>
        </div>

        {/* A–Z as a grid of squares on a black ground. */}
        <nav className="grid grid-cols-9 gap-px border-2 border-black bg-black lg:grid-cols-[repeat(27,minmax(0,1fr))]" aria-label="Browse by initial">
          {LETTERS.map((item) => (
            <button
              type="button"
              key={item}
              className={`grid h-11 place-items-center font-sans text-xs font-bold transition-colors duration-150 ease-linear
                          hover:bg-accent hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-accent ${
                            letter === item ? "bg-black text-white" : "bg-white text-black"
                          }`}
              aria-pressed={letter === item}
              onClick={() => setLetter((current) => (current === item ? "" : item))}
            >
              {item}
            </button>
          ))}
        </nav>

        <p className="font-sans text-xs label-caps text-black" aria-live="polite">
          {loading ? "Searching catalog…" : error ? error : `${pluralize(results.total, "ingredient")} match`}
        </p>

        {loading ? (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <SkeletonCard />
            <SkeletonCard />
            <SkeletonCard />
          </div>
        ) : error ? (
          <EmptyState icon="alertTriangle" title="Catalog unavailable" description={error} />
        ) : results.items.length === 0 ? (
          <EmptyState
            icon="search"
            title="No ingredients match"
            description="Try a shorter INCI fragment, an alternate name such as vitamin C, or clear the function and letter filters."
            action={
              hasFilters ? (
                <Button
                  variant="secondary"
                  onClick={() => {
                    setQuery("");
                    setFunctionFilter("");
                    setLetter("");
                    setEngineOnly(false);
                    setRestrictedOnly(false);
                  }}
                >
                  Clear filters
                </Button>
              ) : null
            }
          />
        ) : (
          <>
            <div className="grid grid-cols-1 gap-0.5 border-2 border-black bg-black sm:grid-cols-2 lg:grid-cols-3">
              {results.items.map((ingredient) => (
                <IngredientCard key={ingredient.id} ingredient={ingredient} onOpen={(item) => setDetailId(item.id)} />
              ))}
            </div>
            {results.has_more ? (
              <div className="flex flex-col items-start gap-3">
                <Button variant="secondary" onClick={loadMore} loading={loadingMore} iconAfter="plus">
                  {loadingMore ? "Loading" : "Load more"}
                </Button>
                {loadMoreError ? (
                  <p className="font-sans text-xs font-bold text-accent-text" role="alert">
                    {loadMoreError}
                  </p>
                ) : null}
              </div>
            ) : null}
          </>
        )}
      </div>

      {detailId ? (
        <IngredientDetail
          ingredient={detail}
          loading={detailLoading}
          error={detailError}
          onClose={() => setDetailId(null)}
          onOpenRelated={setDetailId}
        />
      ) : null}
    </Panel>
  );
}
