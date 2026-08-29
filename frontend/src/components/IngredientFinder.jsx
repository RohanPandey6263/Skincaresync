import { useEffect, useId, useRef, useState } from "react";
import { Panel } from "./ui/Panel.jsx";
import { Button } from "./ui/Button.jsx";
import { Icon } from "./ui/Icon.jsx";
import { Spinner } from "./ui/Spinner.jsx";
import { EmptyState, SkeletonCard } from "./ui/Feedback.jsx";
import { IngredientCard } from "./IngredientCard.jsx";
import { IngredientDetail } from "./IngredientDetail.jsx";
import { useDebouncedValue } from "../hooks/useDebouncedValue.js";
import * as api from "../lib/api.js";
import { formatFunction, pluralize } from "../lib/format.js";

const LETTERS = ["#", ..."ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")];
const PAGE_SIZE = 24;
const TOP_FUNCTIONS = 10;

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
    setLoadingMore(true);
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
      setResults((current) => ({
        ...data,
        items: [...current.items, ...data.items],
      }));
    } catch (err) {
      setError(err.message);
    } finally {
      setLoadingMore(false);
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

  return (
    <Panel
      title="Ingredient catalog"
      icon="book"
      description={
        stats
          ? `${stats.total.toLocaleString()} INCI names from EU CosIng via Open Beauty Facts, plus ${stats.curated} curated engine entries.`
          : "Search official INCI names, synonyms, and CosIng functions."
      }
      className="catalogPanel"
    >
      <div className="catalog">
        <div className="catalogSearch">
          <label className="visuallyHidden" htmlFor={searchId}>
            Search ingredients
          </label>
          <Icon name="search" size={16} className="catalogSearch__icon" />
          <input
            id={searchId}
            ref={searchRef}
            className="input catalogSearch__input"
            value={query}
            placeholder="Search INCI, synonym, or CAS — try tomato, niacinimide, vitamin c"
            autoComplete="off"
            role="combobox"
            aria-autocomplete="list"
            aria-expanded={suggestOpen && suggestions.length > 0}
            aria-controls={listId}
            aria-activedescendant={
              activeSuggest >= 0 ? `${listId}-${suggestions[activeSuggest]?.id}` : undefined
            }
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
              className="catalogSearch__clear"
              aria-label="Clear search"
              onClick={() => {
                setQuery("");
                searchRef.current?.focus();
              }}
            >
              <Icon name="close" size={14} />
            </button>
          ) : null}

          {suggestOpen && suggestions.length > 0 ? (
            <ul className="suggestList" id={listId} role="listbox">
              {suggestions.map((item, index) => (
                <li key={item.id} role="presentation">
                  <button
                    type="button"
                    id={`${listId}-${item.id}`}
                    role="option"
                    aria-selected={index === activeSuggest}
                    className={`suggestList__item${index === activeSuggest ? " is-active" : ""}`}
                    onMouseDown={(event) => event.preventDefault()}
                    onClick={() => applySuggestion(item)}
                  >
                    <span>{item.display_name}</span>
                    <span className="suggestList__meta">
                      {item.functions?.[0] ? formatFunction(item.functions[0]) : item.category || "INCI"}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
        </div>

        <div className="catalogFilters" aria-label="Catalog filters">
          <div className="catalogChips">
            <button
              type="button"
              className={`filterChip${!functionFilter ? " is-active" : ""}`}
              onClick={() => setFunctionFilter("")}
            >
              All functions
            </button>
            {topFunctions.map((item) => (
              <button
                type="button"
                key={item.value}
                className={`filterChip${functionFilter === item.value ? " is-active" : ""}`}
                onClick={() =>
                  setFunctionFilter((current) => (current === item.value ? "" : item.value))
                }
              >
                {formatFunction(item.value)}
                <span className="filterChip__count">{item.count.toLocaleString()}</span>
              </button>
            ))}
            {moreFunctions.length ? (
              <label className="catalogMore">
                <span className="visuallyHidden">More functions</span>
                <select
                  className="input select catalogMore__select"
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
              </label>
            ) : null}
          </div>

          <div className="catalogToggles">
            <label className={`filterChip${engineOnly ? " is-active" : ""}`}>
              <input
                type="checkbox"
                checked={engineOnly}
                onChange={() => setEngineOnly((value) => !value)}
              />
              In compatibility engine
            </label>
            <label className={`filterChip${restrictedOnly ? " is-active" : ""}`}>
              <input
                type="checkbox"
                checked={restrictedOnly}
                onChange={() => setRestrictedOnly((value) => !value)}
              />
              Restricted
            </label>
          </div>
        </div>

        <nav className="letterNav" aria-label="Browse by initial">
          {LETTERS.map((item) => (
            <button
              type="button"
              key={item}
              className={`letterNav__btn${letter === item ? " is-active" : ""}`}
              onClick={() => setLetter((current) => (current === item ? "" : item))}
            >
              {item}
            </button>
          ))}
        </nav>

        <p className="catalogStatus" aria-live="polite">
          {loading
            ? "Searching catalog…"
            : error
              ? error
              : `${pluralize(results.total, "ingredient")} match`}
        </p>

        {loading ? (
          <div className="ingredientGrid">
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
              query || functionFilter || letter || engineOnly || restrictedOnly ? (
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
            <div className="ingredientGrid">
              {results.items.map((ingredient) => (
                <IngredientCard
                  key={ingredient.id}
                  ingredient={ingredient}
                  onOpen={(item) => setDetailId(item.id)}
                />
              ))}
            </div>
            {results.has_more ? (
              <div className="catalogMoreRow">
                <Button variant="secondary" onClick={loadMore} loading={loadingMore}>
                  {loadingMore ? "Loading" : "Load more"}
                </Button>
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
