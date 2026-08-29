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

export function countIngredients(rawIngredientList) {
  if (!rawIngredientList) return 0;
  return rawIngredientList
    .replace(/^\s*ingredients\s*:?/i, "")
    .split(/[,;]/)
    .map((token) => token.trim())
    .filter(Boolean).length;
}

export function isReadyForAnalysis(product) {
  return Boolean(product.name?.trim() && product.raw_ingredient_list?.trim());
}
