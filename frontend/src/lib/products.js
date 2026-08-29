let sequence = 0;

export function createProduct(overrides = {}) {
  sequence += 1;
  return {
    id: `product-${sequence}`,
    brand: "",
    name: "",
    code: "",
    raw_ingredient_list: "",
    image_url: null,
    product_url: null,
    lookupState: "idle",
    lookupMessage: "",
    matchScore: null,
    isExample: false,
    ...overrides,
  };
}

export function createExampleProducts() {
  return {
    am: [
      createProduct({
        brand: "Example",
        name: "Vitamin C Serum",
        raw_ingredient_list: "Ingredients: Water, Ascorbic Acid, Glycerin, Tocopherol",
        lookupState: "success",
        lookupMessage: "Example ingredient list loaded.",
        isExample: true,
      }),
    ],
    pm: [
      createProduct({
        brand: "Example",
        name: "Retinol Night Cream",
        raw_ingredient_list: "Ingredients: Water, Retinol, Glycolic Acid, Niacinamide",
        lookupState: "success",
        lookupMessage: "Example ingredient list loaded.",
        isExample: true,
      }),
    ],
  };
}

// Mirrors skincaresync/parser.py::tokenize_inci. The engine splits on commas at
// parenthesis depth zero only, so "Aqua (Water, Eau), Glycerin" is two
// ingredients. Splitting on /[,;]/ as this used to do reported three, and the
// number shown under a product disagreed with the number actually analysed.
export function countIngredients(rawIngredientList) {
  if (!rawIngredientList) return 0;

  const text = rawIngredientList.replace(/^\s*(ingredients|ingredient list|inci|active ingredients)\s*:\s*/i, "");
  let count = 0;
  let depth = 0;
  let current = "";

  for (const char of text) {
    if (char === "(") {
      depth += 1;
      current += char;
    } else if (char === ")") {
      depth = Math.max(0, depth - 1);
      current += char;
    } else if (char === "," && depth === 0) {
      if (current.trim()) count += 1;
      current = "";
    } else {
      current += char;
    }
  }
  if (current.trim()) count += 1;
  return count;
}

export function isReadyForAnalysis(product) {
  return Boolean(product.name?.trim() && product.raw_ingredient_list?.trim());
}
