import { useEffect, useId, useRef, useState } from "react";
import { useDebouncedValue } from "../hooks/useDebouncedValue.js";
import { countIngredients } from "../lib/products.js";
import * as api from "../lib/api.js";

export function ProductSearchField({ brand, name, onChange, onSelect, disabled = false }) {
  const inputId = useId();
  const listId = `${inputId}-suggestions`;
  const [open, setOpen] = useState(false);
  const [suggestions, setSuggestions] = useState([]);
  const [activeIndex, setActiveIndex] = useState(-1);
  const query = [brand, name].filter(Boolean).join(" ").trim();
  const debouncedQuery = useDebouncedValue(query, 180);
  const requestId = useRef(0);

  useEffect(() => {
    if (debouncedQuery.length < 2) {
      setSuggestions([]);
      return undefined;
    }

    const controller = new AbortController();
    const currentRequest = ++requestId.current;
    api
      .suggestProducts(debouncedQuery, controller.signal)
      .then((items) => {
        if (currentRequest !== requestId.current) return;
        setSuggestions(items);
        setActiveIndex(-1);
      })
      .catch((error) => {
        if (error.name !== "AbortError" && currentRequest === requestId.current) {
          setSuggestions([]);
        }
      });
    return () => controller.abort();
  }, [debouncedQuery]);

  function choose(product) {
    setOpen(false);
    setSuggestions([]);
    onSelect(product);
  }

  function onKeyDown(event) {
    if (!open || !suggestions.length) return;
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setActiveIndex((index) => (index + 1) % suggestions.length);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setActiveIndex((index) => (index - 1 + suggestions.length) % suggestions.length);
    } else if (event.key === "Enter" && activeIndex >= 0) {
      event.preventDefault();
      choose(suggestions[activeIndex]);
    } else if (event.key === "Escape") {
      setOpen(false);
    }
  }

  return (
    <div className="field productSuggest">
      <label className="field__label" htmlFor={inputId}>
        Product name
      </label>
      <input
        id={inputId}
        className="input"
        value={name}
        placeholder="Start typing a product"
        autoComplete="off"
        disabled={disabled}
        role="combobox"
        aria-autocomplete="list"
        aria-expanded={open && suggestions.length > 0}
        aria-controls={listId}
        aria-activedescendant={activeIndex >= 0 ? `${listId}-${activeIndex}` : undefined}
        onChange={(event) => {
          onChange(event.target.value);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        onBlur={() => window.setTimeout(() => setOpen(false), 120)}
        onKeyDown={onKeyDown}
      />

      {open && suggestions.length > 0 ? (
        <ul className="productSuggest__list" id={listId} role="listbox">
          {suggestions.map((product, index) => (
            <li key={`${product.brand}-${product.name}`} role="presentation">
              <button
                id={`${listId}-${index}`}
                type="button"
                role="option"
                aria-selected={index === activeIndex}
                className={`productSuggest__option${index === activeIndex ? " is-active" : ""}`}
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => choose(product)}
              >
                <span className="productSuggest__identity">
                  <span className="productSuggest__name">{product.name}</span>
                  <span className="productSuggest__brand">{product.brand}</span>
                </span>
                <span className="productSuggest__count">
                  {countIngredients(product.raw_ingredient_list)} ingredients
                </span>
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
