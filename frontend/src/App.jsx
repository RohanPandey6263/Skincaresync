import { useState } from "react";

const API_BASE = import.meta.env.VITE_API_URL ?? "http://localhost:8000";
const skinTypes = ["normal", "oily", "dry", "combination", "sensitive"];
const concerns = ["acne", "rosacea", "hyperpigmentation", "eczema", "anti-aging", "dehydration"];

const demoAM = {
  brand: "Demo",
  name: "Vitamin C Serum",
  raw_ingredient_list: "Ingredients: Water, Ascorbic Acid, Glycerin, Tocopherol",
};

const demoPM = {
  brand: "Demo",
  name: "Retinol Night Cream",
  raw_ingredient_list: "Ingredients: Water, Retinol, Glycolic Acid, Niacinamide",
};

function emptyProduct(name) {
  return { brand: "", name, raw_ingredient_list: "" };
}

function ProductEditor({ title, products, onChange, onAdd }) {
  function updateProduct(index, field, value) {
    onChange(products.map((product, idx) => (idx === index ? { ...product, [field]: value } : product)));
  }

  function removeProduct(index) {
    onChange(products.filter((_, idx) => idx !== index));
  }

  return (
    <section className="panel">
      <div className="sectionHeader">
        <h2>{title}</h2>
        <button type="button" onClick={onAdd}>Add product</button>
      </div>
      <div className="productList">
        {products.map((product, index) => (
          <article className="productCard" key={`${title}-${index}`}>
            <div className="productHeader">
              <strong>Product {index + 1}</strong>
              {products.length > 1 && (
                <button type="button" className="linkButton" onClick={() => removeProduct(index)}>
                  Remove
                </button>
              )}
            </div>
            <label>
              Brand
              <input
                value={product.brand}
                onChange={(event) => updateProduct(index, "brand", event.target.value)}
                placeholder="The Ordinary"
              />
            </label>
            <label>
              Product name
              <input
                value={product.name}
                onChange={(event) => updateProduct(index, "name", event.target.value)}
                placeholder="Retinol 0.2% in Squalane"
              />
            </label>
            <label>
              Ingredient list
              <textarea
                value={product.raw_ingredient_list}
                onChange={(event) => updateProduct(index, "raw_ingredient_list", event.target.value)}
                placeholder="Ingredients: Water, Retinol, Glycerin..."
                rows={5}
              />
            </label>
          </article>
        ))}
      </div>
    </section>
  );
}

function ScoreBadge({ score }) {
  if (!score) return null;
  const className = `score ${score.status}`;
  if (score.status === "conflict") {
    return <div className={className}>Conflict: {score.high} high, {score.medium} medium</div>;
  }
  if (score.status === "caution") {
    return <div className={className}>Caution: {score.count} item{score.count === 1 ? "" : "s"}</div>;
  }
  return <div className={className}>Clean routine</div>;
}

function ResultCard({ item }) {
  return (
    <article className={`resultCard ${item.severity}`}>
      <div className="resultTopline">
        <span>{item.interaction_type}</span>
        <strong>{item.severity}</strong>
      </div>
      <h3>{item.ingredient_a.inci_name} + {item.ingredient_b.inci_name}</h3>
      <p>{item.description || item.mechanism}</p>
      <dl>
        <div>
          <dt>Scope</dt>
          <dd>{item.scope}</dd>
        </div>
        <div>
          <dt>Products</dt>
          <dd>{item.product_a.label} and {item.product_b.label}</dd>
        </div>
        <div>
          <dt>Source</dt>
          <dd>{item.source_citation || "Needs advisor review"}</dd>
        </div>
      </dl>
    </article>
  );
}

function UnknownPair({ item }) {
  return (
    <article className="unknownCard">
      <strong>{item.ingredient_a.inci_name} + {item.ingredient_b.inci_name}</strong>
      <span>{item.scope}</span>
      <p>{item.message}</p>
    </article>
  );
}

function Results({ result }) {
  if (!result) {
    return (
      <section className="emptyState">
        <h2>Ready to analyze</h2>
        <p>Add products to the morning and evening routines, then run the compatibility check.</p>
      </section>
    );
  }

  return (
    <section className="results">
      <div className="resultsHeader">
        <h2>Compatibility Results</h2>
        <ScoreBadge score={result.overall_score} />
      </div>

      {result.conflicts.length > 0 && (
        <div className="resultSection">
          <h3>Conflicts</h3>
          {result.conflicts.map((item) => <ResultCard item={item} key={`conflict-${item.interaction_id}-${item.scope}`} />)}
        </div>
      )}

      {result.cautions.length > 0 && (
        <div className="resultSection">
          <h3>Cautions</h3>
          {result.cautions.map((item) => <ResultCard item={item} key={`caution-${item.interaction_id}-${item.scope}`} />)}
        </div>
      )}

      {result.synergies.length > 0 && (
        <div className="resultSection">
          <h3>Synergies</h3>
          {result.synergies.map((item) => <ResultCard item={item} key={`synergy-${item.interaction_id}-${item.scope}`} />)}
        </div>
      )}

      {result.unknown_pairs.length > 0 && (
        <div className="resultSection">
          <h3>Unknown Pairs Logged</h3>
          {result.unknown_pairs.slice(0, 12).map((item, index) => <UnknownPair item={item} key={`unknown-${index}`} />)}
        </div>
      )}

      {result.unresolved_tokens.length > 0 && (
        <div className="resultSection">
          <h3>Unresolved Ingredients</h3>
          <div className="tokenGrid">
            {result.unresolved_tokens.map((item, index) => (
              <span key={`${item.raw_token}-${index}`}>{item.raw_token}</span>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}

function Backlog({ gaps, onRefresh, loading }) {
  return (
    <section className="panel">
      <div className="sectionHeader">
        <h2>Research Backlog</h2>
        <button type="button" onClick={onRefresh} disabled={loading}>
          {loading ? "Loading..." : "Refresh"}
        </button>
      </div>
      {gaps.length === 0 ? (
        <p className="muted">Unknown ingredient pairs will appear here after analysis.</p>
      ) : (
        <div className="gapList">
          {gaps.map((gap) => (
            <article className="gapItem" key={gap.interaction_gap_id}>
              <strong>{gap.ingredient_a} + {gap.ingredient_b}</strong>
              <span>{gap.query_count} hit{gap.query_count === 1 ? "" : "s"} · {gap.status}</span>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}

export default function App() {
  const [skinType, setSkinType] = useState("normal");
  const [selectedConcerns, setSelectedConcerns] = useState([]);
  const [amProducts, setAmProducts] = useState([demoAM]);
  const [pmProducts, setPmProducts] = useState([demoPM]);
  const [result, setResult] = useState(null);
  const [gaps, setGaps] = useState([]);
  const [loading, setLoading] = useState(false);
  const [gapLoading, setGapLoading] = useState(false);
  const [error, setError] = useState("");

  function toggleConcern(concern) {
    setSelectedConcerns((current) =>
      current.includes(concern)
        ? current.filter((item) => item !== concern)
        : [...current, concern],
    );
  }

  async function analyzeRoutine() {
    setLoading(true);
    setError("");
    try {
      const response = await fetch(`${API_BASE}/api/analyze`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          skin_profile: {
            skin_type: skinType,
            concerns: selectedConcerns,
          },
          am_products: amProducts.filter((product) => product.name && product.raw_ingredient_list),
          pm_products: pmProducts.filter((product) => product.name && product.raw_ingredient_list),
        }),
      });

      if (!response.ok) {
        throw new Error(`API request failed with ${response.status}`);
      }

      setResult(await response.json());
      await loadGaps();
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  async function loadGaps() {
    setGapLoading(true);
    try {
      const response = await fetch(`${API_BASE}/api/gaps`);
      if (!response.ok) {
        throw new Error(`Gap request failed with ${response.status}`);
      }
      setGaps(await response.json());
    } catch (err) {
      setError(err.message);
    } finally {
      setGapLoading(false);
    }
  }

  return (
    <main>
      <header className="hero">
        <p className="eyebrow">SkincareSync MVP</p>
        <h1>Routine-level skincare compatibility analysis</h1>
        <p>
          Analyze AM and PM products with a deterministic rules engine backed by your ingredient database.
        </p>
      </header>

      <div className="layout">
        <div className="builder">
          <section className="panel">
            <h2>Skin Profile</h2>
            <label>
              Skin type
              <select value={skinType} onChange={(event) => setSkinType(event.target.value)}>
                {skinTypes.map((type) => <option key={type} value={type}>{type}</option>)}
              </select>
            </label>
            <div className="concerns">
              <span>Concerns</span>
              <div className="checkboxGrid">
                {concerns.map((concern) => (
                  <label className="checkbox" key={concern}>
                    <input
                      type="checkbox"
                      checked={selectedConcerns.includes(concern)}
                      onChange={() => toggleConcern(concern)}
                    />
                    {concern}
                  </label>
                ))}
              </div>
            </div>
          </section>

          <ProductEditor
            title="Morning Routine"
            products={amProducts}
            onChange={setAmProducts}
            onAdd={() => setAmProducts([...amProducts, emptyProduct("Morning product")])}
          />

          <ProductEditor
            title="Evening Routine"
            products={pmProducts}
            onChange={setPmProducts}
            onAdd={() => setPmProducts([...pmProducts, emptyProduct("Evening product")])}
          />

          <div className="actions">
            <button type="button" className="primary" onClick={analyzeRoutine} disabled={loading}>
              {loading ? "Analyzing..." : "Analyze Routine"}
            </button>
            {error && <p className="error">{error}</p>}
          </div>
        </div>

        <Results result={result} />
        <Backlog gaps={gaps} onRefresh={loadGaps} loading={gapLoading} />
      </div>
    </main>
  );
}

