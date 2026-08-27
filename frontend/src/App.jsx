import { useEffect, useRef, useState } from "react";

const API_BASE = import.meta.env.VITE_API_URL ?? "http://localhost:8000";
const skinTypes = ["normal", "oily", "dry", "combination", "sensitive"];
const concerns = ["acne", "rosacea", "hyperpigmentation", "eczema", "anti-aging", "dehydration"];

const demoAM = {
  brand: "Demo",
  name: "Vitamin C Serum",
  code: "",
  raw_ingredient_list: "Ingredients: Water, Ascorbic Acid, Glycerin, Tocopherol",
};

const demoPM = {
  brand: "Demo",
  name: "Retinol Night Cream",
  code: "",
  raw_ingredient_list: "Ingredients: Water, Retinol, Glycolic Acid, Niacinamide",
};

function emptyProduct(name) {
  return { brand: "", name, code: "", raw_ingredient_list: "", lookup_status: "" };
}

function ProductEditor({ title, products, onChange, onAdd, onLookupCode, onSearchProduct, onScanCode }) {
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
              Barcode or QR code
              <div className="inlineControls">
                <input
                  value={product.code || ""}
                  onChange={(event) => updateProduct(index, "code", event.target.value)}
                  placeholder="Scan or paste product code"
                />
                <button type="button" onClick={() => onLookupCode(index)}>Lookup</button>
                <button type="button" onClick={() => onScanCode(index)}>Scan</button>
              </div>
            </label>
            <button type="button" className="secondaryAction" onClick={() => onSearchProduct(index)}>
              Find ingredients from brand and product name
            </button>
            <p className={product.raw_ingredient_list ? "lookupStatus success" : "lookupStatus"}>
              {product.lookup_status || (product.raw_ingredient_list ? "Ingredient list found." : "Find the product to load its ingredient list.")}
            </p>
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
          <dd>{item.source_citation || "Source review pending"}</dd>
        </div>
      </dl>
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
  const videoRef = useRef(null);
  const [skinType, setSkinType] = useState("normal");
  const [selectedConcerns, setSelectedConcerns] = useState([]);
  const [amProducts, setAmProducts] = useState([demoAM]);
  const [pmProducts, setPmProducts] = useState([demoPM]);
  const [result, setResult] = useState(null);
  const [gaps, setGaps] = useState([]);
  const [loading, setLoading] = useState(false);
  const [gapLoading, setGapLoading] = useState(false);
  const [scanner, setScanner] = useState(null);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!scanner || !videoRef.current) return undefined;

    let cancelled = false;
    const video = videoRef.current;
    video.srcObject = scanner.stream;

    async function scanFrame() {
      if (cancelled) return;
      try {
        await video.play();
        const detector = new window.BarcodeDetector({
          formats: ["qr_code", "ean_13", "ean_8", "upc_a", "upc_e", "code_128"],
        });
        const codes = await detector.detect(video);
        if (codes.length > 0) {
          const rawValue = codes[0].rawValue;
          scanner.stream.getTracks().forEach((track) => track.stop());
          setScanner(null);
          setProductField(scanner.routine, scanner.index, "code", rawValue);
          lookupCode(scanner.routine, scanner.index, rawValue);
          return;
        }
      } catch (err) {
        setError(err.message);
      }
      requestAnimationFrame(scanFrame);
    }

    scanFrame();

    return () => {
      cancelled = true;
    };
  }, [scanner]);

  function toggleConcern(concern) {
    setSelectedConcerns((current) =>
      current.includes(concern)
        ? current.filter((item) => item !== concern)
        : [...current, concern],
    );
  }

  function setProductField(routine, index, field, value) {
    const setter = routine === "am" ? setAmProducts : setPmProducts;
    setter((products) => products.map((product, idx) => (idx === index ? { ...product, [field]: value } : product)));
  }

  function updateProductFromLookup(routine, index, product) {
    const status = product.similarity_score
      ? `Matched ${product.brand || "Unknown brand"} ${product.name} (${product.similarity_score}% match).`
      : "Ingredient list found.";
    const setter = routine === "am" ? setAmProducts : setPmProducts;
    setter((products) =>
      products.map((current, idx) =>
        idx === index
          ? {
              ...current,
              brand: current.brand || product.brand || "",
              name: product.name || current.name,
              code: product.code || current.code || "",
              raw_ingredient_list: product.raw_ingredient_list,
              lookup_status: status,
            }
          : current,
      ),
    );
  }

  function getProduct(routine, index) {
    return (routine === "am" ? amProducts : pmProducts)[index];
  }

  async function lookupCode(routine, index, explicitCode) {
    const product = getProduct(routine, index);
    const code = explicitCode || product.code;
    if (!code) {
      setError("Enter or scan a product code first.");
      setProductField(routine, index, "lookup_status", "Enter or scan a product code first.");
      return;
    }
    setError("");
    setProductField(routine, index, "lookup_status", "Looking up product code...");
    try {
      const params = new URLSearchParams({ value: code });
      const response = await fetch(`${API_BASE}/api/products/code?${params}`);
      if (!response.ok) {
        throw new Error("No ingredient list found for that code.");
      }
      updateProductFromLookup(routine, index, await response.json());
    } catch (err) {
      setError(err.message);
      setProductField(routine, index, "lookup_status", err.message);
    }
  }

  async function searchProduct(routine, index) {
    const product = getProduct(routine, index);
    if (!product.brand && !product.name) {
      setError("Enter a brand or product name first.");
      setProductField(routine, index, "lookup_status", "Enter a brand or product name first.");
      return;
    }
    setError("");
    setProductField(routine, index, "lookup_status", "Searching for ingredient list...");
    const params = new URLSearchParams({ brand: product.brand || "", name: product.name || "" });
    try {
      const response = await fetch(`${API_BASE}/api/products/search?${params}`);
      if (!response.ok) {
        throw new Error("Product search failed.");
      }
      const matches = await response.json();
      if (matches.length === 0) {
        throw new Error("No matching ingredient list found.");
      }
      if (matches[0].similarity_score !== null && matches[0].similarity_score < 35) {
        throw new Error("No confident product match found. Try adding more detail.");
      }
      updateProductFromLookup(routine, index, matches[0]);
    } catch (err) {
      setError(err.message);
      setProductField(routine, index, "lookup_status", err.message);
    }
  }

  async function startScan(routine, index) {
    if (!("BarcodeDetector" in window)) {
      setError("This browser does not support camera code scanning. Paste the barcode or QR code instead.");
      setProductField(routine, index, "lookup_status", "Camera scanning is not supported in this browser. Paste the code instead.");
      return;
    }
    if (!navigator.mediaDevices?.getUserMedia) {
      setError("Camera access is not available in this browser.");
      setProductField(routine, index, "lookup_status", "Camera access is not available in this browser.");
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment" },
      });
      setScanner({ routine, index, stream });
      setProductField(routine, index, "lookup_status", "Scanning for product code...");
      setError("");
    } catch (err) {
      setError(err.message);
      setProductField(routine, index, "lookup_status", err.message);
    }
  }

  function stopScan() {
    if (scanner?.stream) {
      scanner.stream.getTracks().forEach((track) => track.stop());
    }
    setScanner(null);
  }

  async function analyzeRoutine() {
    const foundAmProducts = amProducts.filter((product) => product.name && product.raw_ingredient_list);
    const foundPmProducts = pmProducts.filter((product) => product.name && product.raw_ingredient_list);
    if (foundAmProducts.length + foundPmProducts.length < 2) {
      setError("Find ingredient lists for at least two products before analyzing.");
      return;
    }

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
          am_products: foundAmProducts,
          pm_products: foundPmProducts,
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
            onLookupCode={(index) => lookupCode("am", index)}
            onSearchProduct={(index) => searchProduct("am", index)}
            onScanCode={(index) => startScan("am", index)}
          />

          <ProductEditor
            title="Evening Routine"
            products={pmProducts}
            onChange={setPmProducts}
            onAdd={() => setPmProducts([...pmProducts, emptyProduct("Evening product")])}
            onLookupCode={(index) => lookupCode("pm", index)}
            onSearchProduct={(index) => searchProduct("pm", index)}
            onScanCode={(index) => startScan("pm", index)}
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
      {scanner && (
        <div className="scannerOverlay">
          <div className="scannerPanel">
            <div className="sectionHeader">
              <h2>Scan product code</h2>
              <button type="button" onClick={stopScan}>Cancel</button>
            </div>
            <video ref={videoRef} playsInline muted />
            <p className="muted">Point the camera at a barcode or QR code. The ingredient list will fill in if the product is found.</p>
          </div>
        </div>
      )}
    </main>
  );
}

