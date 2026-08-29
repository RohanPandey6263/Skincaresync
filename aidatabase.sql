-- SkincareSync MVP schema.
-- This migration reuses the existing public.ingredients table:
--   ingridient_id, inci_name, synonyms, category, ph_min, ph_max, comodogenic, created_at

CREATE TABLE IF NOT EXISTS interactions (
    interaction_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingredient_a_id INTEGER NOT NULL REFERENCES ingredients(ingridient_id) ON DELETE CASCADE,
    ingredient_b_id INTEGER NOT NULL REFERENCES ingredients(ingridient_id) ON DELETE CASCADE,
    interaction_type TEXT NOT NULL CHECK (interaction_type IN ('conflict', 'caution', 'synergy', 'redundant')),
    severity TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high')),
    conflict_scope TEXT NOT NULL DEFAULT 'both' CHECK (conflict_scope IN ('direct', 'cumulative', 'both')),
    mechanism TEXT NOT NULL,
    description TEXT,
    source_citation TEXT,
    confidence TEXT NOT NULL DEFAULT 'provisional' CHECK (confidence IN ('verified', 'provisional', 'low')),
    skin_type_modifier JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT interactions_distinct_ingredients CHECK (ingredient_a_id <> ingredient_b_id)
);

CREATE TABLE IF NOT EXISTS products (
    product_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    brand TEXT,
    name TEXT NOT NULL,
    barcode TEXT UNIQUE,
    raw_ingredient_list TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'open_beauty_facts', 'user_submitted')),
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

-- Saved routines (skin_profiles, routines, routine_products) were defined here
-- but never built: the API analyses a routine from the request body and keeps
-- nothing between requests. Dropped in migration 006. If the feature is ever
-- picked up, recover the original DDL from `git show c2279f9:aidatabase.sql` --
-- though it is worth redesigning rather than restoring, since it predates the
-- product catalog.

CREATE TABLE IF NOT EXISTS parser_unknowns (
    parser_unknown_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    raw_token TEXT NOT NULL UNIQUE,
    normalized_token TEXT NOT NULL,
    source_product TEXT,
    occurrence_count INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'pending_review' CHECK (status IN ('pending_review', 'mapped', 'ignored')),
    first_seen TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS interaction_gaps (
    interaction_gap_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingredient_a_id INTEGER NOT NULL REFERENCES ingredients(ingridient_id) ON DELETE CASCADE,
    ingredient_b_id INTEGER NOT NULL REFERENCES ingredients(ingridient_id) ON DELETE CASCADE,
    user_skin_type TEXT,
    user_concerns TEXT[] NOT NULL DEFAULT '{}',
    query_count INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'pending_review' CHECK (
        status IN ('pending_review', 'in_research', 'verified', 'published', 'insufficient_evidence')
    ),
    first_seen TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT interaction_gaps_distinct_ingredients CHECK (ingredient_a_id <> ingredient_b_id)
);

CREATE INDEX IF NOT EXISTS idx_ingredients_inci_lower ON ingredients (LOWER(inci_name));
CREATE INDEX IF NOT EXISTS idx_interactions_pair ON interactions (ingredient_a_id, ingredient_b_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_interactions_unique_pair
    ON interactions (
        LEAST(ingredient_a_id, ingredient_b_id),
        GREATEST(ingredient_a_id, ingredient_b_id),
        interaction_type,
        conflict_scope
    );
CREATE INDEX IF NOT EXISTS idx_interaction_gaps_query_count ON interaction_gaps (query_count DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_interaction_gaps_unique_pair
    ON interaction_gaps (
        LEAST(ingredient_a_id, ingredient_b_id),
        GREATEST(ingredient_a_id, ingredient_b_id),
        COALESCE(user_skin_type, '')
    );
CREATE INDEX IF NOT EXISTS idx_parser_unknowns_occurrence_count ON parser_unknowns (occurrence_count DESC);

WITH retinol AS (
    SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'retinol'
),
glycolic AS (
    SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'glycolic acid'
)
INSERT INTO interactions (
    ingredient_a_id,
    ingredient_b_id,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    confidence,
    skin_type_modifier
)
SELECT
    retinol.ingridient_id,
    glycolic.ingridient_id,
    'conflict',
    'high',
    'both',
    'Potential irritation from combining retinoids with alpha hydroxy acid exfoliation.',
    'Retinol and glycolic acid can be irritating when layered or overused in the same routine.',
    'PMID:33377285',
    'provisional',
    '{"sensitive": "high", "dry": "high", "oily": "medium", "combination": "high", "normal": "medium"}'::jsonb
FROM retinol, glycolic
ON CONFLICT DO NOTHING;

WITH benzoyl AS (
    SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'benzoyl peroxide'
),
retinol AS (
    SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'retinol'
)
INSERT INTO interactions (
    ingredient_a_id,
    ingredient_b_id,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    confidence,
    skin_type_modifier
)
SELECT
    benzoyl.ingridient_id,
    retinol.ingridient_id,
    'caution',
    'medium',
    'direct',
    'Potential irritation and reduced tolerability when strong acne actives are combined.',
    'Use caution when combining benzoyl peroxide and retinol, especially for sensitive skin.',
    'PMID:38300170',
    'provisional',
    '{"sensitive": "high", "dry": "high"}'::jsonb
FROM benzoyl, retinol
ON CONFLICT DO NOTHING;

WITH ascorbic AS (
    SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'ascorbic acid'
),
glycolic AS (
    SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'glycolic acid'
)
INSERT INTO interactions (
    ingredient_a_id,
    ingredient_b_id,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    confidence,
    skin_type_modifier
)
SELECT
    ascorbic.ingridient_id,
    glycolic.ingridient_id,
    'caution',
    'high',
    'both',
    'Layering low-pH vitamin C with alpha hydroxy acid exfoliation can increase irritation risk.',
    'This combination may be too irritating for some routines, especially when used daily or on sensitive skin.',
    'PMID:35642229',
    'provisional',
    '{"sensitive": "high", "dry": "high", "combination": "high", "normal": "medium", "oily": "medium"}'::jsonb
FROM ascorbic, glycolic
ON CONFLICT DO NOTHING;

WITH ascorbic AS (
    SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'ascorbic acid'
),
retinol AS (
    SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'retinol'
)
INSERT INTO interactions (
    ingredient_a_id,
    ingredient_b_id,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    confidence,
    skin_type_modifier
)
SELECT
    ascorbic.ingridient_id,
    retinol.ingridient_id,
    'caution',
    'medium',
    'cumulative',
    'Using strong vitamin C and retinol across the same daily routine can increase dryness and irritation for some users.',
    'Consider separating these actives or reducing frequency if irritation occurs.',
    'PMID:37169404',
    'provisional',
    '{"sensitive": "high", "dry": "high"}'::jsonb
FROM ascorbic, retinol
ON CONFLICT DO NOTHING;

WITH niacinamide AS (
    SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'niacinamide'
),
glycolic AS (
    SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'glycolic acid'
)
INSERT INTO interactions (
    ingredient_a_id,
    ingredient_b_id,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    confidence,
    skin_type_modifier
)
SELECT
    niacinamide.ingridient_id,
    glycolic.ingridient_id,
    'caution',
    'low',
    'direct',
    'Low-pH exfoliating acids can make some barrier-support ingredients less tolerable when layered.',
    'This is usually manageable, but sensitive users should watch for flushing or irritation.',
    'PMID:40233838',
    'provisional',
    '{"sensitive": "medium"}'::jsonb
FROM niacinamide, glycolic
ON CONFLICT DO NOTHING;

WITH rule_seed (
    ingredient_a,
    ingredient_b,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    skin_type_modifier
) AS (
    VALUES
    ('Retinol', 'Lactic Acid', 'caution', 'high', 'both', 'Retinoids and alpha hydroxy acids can increase irritation when layered or overused.', 'Use caution combining retinol with lactic acid, especially in sensitive or dry skin routines.', 'PMID:33377285', '{"sensitive": "high", "dry": "high", "normal": "medium", "oily": "medium"}'::jsonb),
    ('Retinol', 'Mandelic Acid', 'caution', 'medium', 'both', 'Retinoids and exfoliating acids may compound dryness and barrier irritation.', 'This combination is usually better introduced slowly and not started on the same day.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinol', 'Salicylic Acid', 'caution', 'high', 'both', 'Retinoids and beta hydroxy acids can increase dryness, peeling, and irritation.', 'Use caution when combining retinol with salicylic acid in the same daily routine.', 'PMID:26516077', '{"sensitive": "high", "dry": "high", "normal": "medium", "oily": "medium"}'::jsonb),
    ('Retinol', 'Betaine Salicylate', 'caution', 'medium', 'both', 'Retinoids and salicylate exfoliants may compound irritation.', 'This pairing should be introduced gradually and watched for dryness or stinging.', 'PMID:26516077', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinol', 'Gluconolactone', 'caution', 'medium', 'both', 'Retinoids and exfoliating acids may be irritating when combined frequently.', 'This lower-strength acid pairing is still worth spacing out for sensitive routines.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinol', 'Lactobionic Acid', 'caution', 'medium', 'both', 'Retinoids and exfoliating acids may increase dryness when combined.', 'This pairing is lower risk than stronger acids but can still irritate sensitive skin.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinal', 'Glycolic Acid', 'caution', 'high', 'both', 'Retinoids and glycolic acid exfoliation can compound irritation.', 'Retinal and glycolic acid should be combined cautiously, especially in frequent routines.', 'PMID:33377285', '{"sensitive": "high", "dry": "high", "normal": "medium", "oily": "medium"}'::jsonb),
    ('Retinal', 'Lactic Acid', 'caution', 'high', 'both', 'Retinoids and alpha hydroxy acids can increase irritation.', 'Retinal and lactic acid may be too much when layered or used nightly.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinal', 'Salicylic Acid', 'caution', 'high', 'both', 'Retinoids and beta hydroxy acids can increase dryness and peeling.', 'Use caution combining retinal with salicylic acid, especially for acne routines already using multiple actives.', 'PMID:26516077', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Tretinoin', 'Glycolic Acid', 'caution', 'high', 'direct', 'Prescription-strength retinoids and glycolic acid can be irritating when layered.', 'Avoid starting tretinoin and glycolic acid together without a slow introduction plan.', 'PMID:33377285', '{"sensitive": "high", "dry": "high", "normal": "high", "oily": "medium"}'::jsonb),
    ('Tretinoin', 'Lactic Acid', 'caution', 'high', 'both', 'Prescription-strength retinoids and exfoliating acids can compound irritation.', 'Tretinoin and lactic acid should be used cautiously in the same routine schedule.', 'PMID:33377285', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Tretinoin', 'Salicylic Acid', 'caution', 'high', 'direct', 'Prescription-strength retinoids and beta hydroxy acids can increase irritation.', 'Tretinoin plus salicylic acid can be drying and should not be introduced aggressively.', 'PMID:26516077', '{"sensitive": "high", "dry": "high", "normal": "medium", "oily": "medium"}'::jsonb),
    ('Adapalene', 'Glycolic Acid', 'caution', 'medium', 'both', 'Adapalene and alpha hydroxy acid exfoliation can increase dryness and irritation.', 'This acne-active pairing should be introduced gradually and watched for peeling.', 'PMID:38300170', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Adapalene', 'Salicylic Acid', 'caution', 'medium', 'both', 'Adapalene and salicylic acid can be irritating when combined frequently.', 'Use caution combining adapalene with salicylic acid, especially early in a routine.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Adapalene', 'Lactic Acid', 'caution', 'medium', 'both', 'Adapalene and alpha hydroxy acid exfoliation may compound dryness.', 'This pairing is not automatically unsafe, but frequency matters.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Benzoyl Peroxide', 'Retinal', 'caution', 'high', 'direct', 'Benzoyl peroxide and retinoids can increase dryness and irritation when layered.', 'Use caution layering benzoyl peroxide with retinal in the same routine.', 'PMID:38300170', '{"sensitive": "high", "dry": "high", "normal": "medium", "oily": "medium"}'::jsonb),
    ('Benzoyl Peroxide', 'Retinyl Palmitate', 'caution', 'medium', 'direct', 'Benzoyl peroxide and retinoid-family ingredients may compound irritation.', 'This pairing can be drying for some users, especially with frequent use.', 'PMID:38300170', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Benzoyl Peroxide', 'Tretinoin', 'caution', 'high', 'direct', 'Benzoyl peroxide and prescription-strength retinoids can increase irritation.', 'Use caution combining benzoyl peroxide with tretinoin in the same routine.', 'PMID:38300170', '{"sensitive": "high", "dry": "high", "normal": "high", "oily": "medium"}'::jsonb),
    ('Benzoyl Peroxide', 'Adapalene', 'synergy', 'medium', 'direct', 'Adapalene and benzoyl peroxide are commonly combined acne actives.', 'This combination can be effective for acne but may still be drying or irritating.', 'PMID:34674160', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Benzoyl Peroxide', 'Salicylic Acid', 'caution', 'high', 'both', 'Multiple acne exfoliating/antibacterial actives can increase dryness and irritation.', 'Benzoyl peroxide and salicylic acid together can be harsh for many routines.', 'PMID:32356369', '{"sensitive": "high", "dry": "high", "normal": "medium", "oily": "medium"}'::jsonb),
    ('Benzoyl Peroxide', 'Glycolic Acid', 'caution', 'high', 'both', 'Benzoyl peroxide plus acid exfoliation can compound irritation.', 'This pairing may be too aggressive when used frequently or layered directly.', 'PMID:32356369', '{"sensitive": "high", "dry": "high", "normal": "medium", "oily": "medium"}'::jsonb),
    ('Benzoyl Peroxide', 'Ascorbic Acid', 'caution', 'medium', 'direct', 'Oxidizing acne actives and antioxidant vitamin C can be hard to layer tolerably.', 'This pairing is best separated if the user experiences stinging, dryness, or reduced tolerance.', 'PMID:40233838', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Ascorbic Acid', 'Lactic Acid', 'caution', 'high', 'direct', 'Low-pH vitamin C and alpha hydroxy acids can increase irritation when layered.', 'Use caution combining ascorbic acid with lactic acid in the same routine.', 'PMID:35642229', '{"sensitive": "high", "dry": "high", "normal": "medium", "oily": "medium"}'::jsonb),
    ('Ascorbic Acid', 'Mandelic Acid', 'caution', 'medium', 'direct', 'Low-pH vitamin C and exfoliating acids can increase stinging or dryness.', 'This pairing is usually better spaced out for sensitive routines.', 'PMID:35642229', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Ascorbic Acid', 'Salicylic Acid', 'caution', 'medium', 'direct', 'Low-pH vitamin C and beta hydroxy acid exfoliation can compound irritation.', 'Use caution if combining ascorbic acid with salicylic acid in the same routine.', 'PMID:35642229', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Sodium Ascorbyl Phosphate', 'Glycolic Acid', 'caution', 'low', 'direct', 'Vitamin C derivatives and exfoliating acids can increase irritation in some routines.', 'This is a lower-risk vitamin C derivative pairing, but sensitive users should monitor tolerance.', 'PMID:35642229', '{"sensitive": "medium"}'::jsonb),
    ('Sodium Ascorbyl Phosphate', 'Salicylic Acid', 'caution', 'low', 'direct', 'Vitamin C derivatives and exfoliating acids can add to irritation load.', 'This pairing is usually tolerable but may be drying for sensitive routines.', 'PMID:35642229', '{"sensitive": "medium"}'::jsonb),
    ('Ascorbyl Glucoside', 'Glycolic Acid', 'caution', 'low', 'direct', 'Vitamin C derivatives and alpha hydroxy acids can add to irritation load.', 'This is a lower-risk pairing but still worth introducing gradually.', 'PMID:35642229', '{"sensitive": "medium"}'::jsonb),
    ('Niacinamide', 'Ascorbic Acid', 'synergy', 'low', 'both', 'Niacinamide and vitamin C are both used for tone and barrier-support routines.', 'This pairing can be complementary for brightening-focused routines.', 'PMID:40233838', '{}'::jsonb),
    ('Niacinamide', 'Retinol', 'synergy', 'low', 'both', 'Niacinamide can support tolerability in routines using retinoids.', 'This pairing can be helpful when retinoid routines need barrier support.', 'PMID:40233838', '{}'::jsonb),
    ('Niacinamide', 'Benzoyl Peroxide', 'synergy', 'low', 'direct', 'Niacinamide can support acne-prone routines using stronger acne actives.', 'This pairing may be useful in acne routines where barrier support is needed.', 'PMID:38300170', '{}'::jsonb),
    ('Hydroquinone', 'Tretinoin', 'synergy', 'medium', 'cumulative', 'Hydroquinone and tretinoin are used together in melasma-focused topical regimens.', 'This pairing can be part of hyperpigmentation routines but should be handled carefully due to irritation potential.', 'PMID:31802394', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Hydroquinone', 'Retinol', 'caution', 'medium', 'cumulative', 'Brightening agents and retinoids can increase irritation burden.', 'Hydroquinone and retinol may be irritating when introduced together.', 'PMID:31802394', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Hydroquinone', 'Glycolic Acid', 'caution', 'medium', 'direct', 'Hydroquinone and exfoliating acids can increase irritation in pigment routines.', 'This pairing can be harsh if layered frequently.', 'PMID:35642229', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Hydroquinone', 'Ascorbic Acid', 'synergy', 'low', 'cumulative', 'Multiple pigment-focused actives can be complementary in hyperpigmentation routines.', 'This pairing can support brightening goals but should be monitored for irritation.', 'PMID:35642229', '{"sensitive": "medium"}'::jsonb),
    ('Kojic Acid', 'Glycolic Acid', 'caution', 'medium', 'direct', 'Brightening acids and exfoliating acids can compound irritation.', 'Kojic acid and glycolic acid should be layered cautiously in sensitive routines.', 'PMID:35642229', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Kojic Acid', 'Ascorbic Acid', 'synergy', 'low', 'cumulative', 'Kojic acid and vitamin C are both used in pigment-focused topical care.', 'This pairing can be complementary for brightening routines.', 'PMID:35642229', '{}'::jsonb),
    ('Alpha Arbutin', 'Ascorbic Acid', 'synergy', 'low', 'cumulative', 'Arbutin and vitamin C are used for hyperpigmentation-focused routines.', 'This pairing can be complementary for tone-evening goals.', 'PMID:35642229', '{}'::jsonb),
    ('Tranexamic Acid', 'Hydroquinone', 'synergy', 'medium', 'cumulative', 'Tranexamic acid and hydroquinone are both used in melasma and hyperpigmentation care.', 'This pairing can be complementary in pigment-focused routines while still requiring irritation monitoring.', 'PMID:31802394', '{"sensitive": "medium"}'::jsonb),
    ('Tranexamic Acid', 'Ascorbic Acid', 'synergy', 'low', 'cumulative', 'Tranexamic acid and vitamin C are both used in hyperpigmentation-focused topical care.', 'This pairing can support brightening routines without being a direct conflict.', 'PMID:35642229', '{}'::jsonb),
    ('Azelaic Acid', 'Salicylic Acid', 'caution', 'medium', 'direct', 'Azelaic acid and salicylic acid can compound dryness and irritation.', 'This acne-focused pairing should be introduced gradually.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Azelaic Acid', 'Glycolic Acid', 'caution', 'medium', 'direct', 'Azelaic acid and alpha hydroxy acids can increase irritation.', 'This pairing may be too irritating for sensitive routines when layered directly.', 'PMID:35642229', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Azelaic Acid', 'Retinol', 'caution', 'medium', 'cumulative', 'Azelaic acid and retinoids can add to irritation burden.', 'This pairing can be useful for acne or pigment routines but should be introduced slowly.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Azelaic Acid', 'Benzoyl Peroxide', 'caution', 'medium', 'direct', 'Combining multiple acne actives can increase dryness and irritation.', 'Azelaic acid and benzoyl peroxide may be too harsh when layered directly.', 'PMID:38300170', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Azelaic Acid', 'Niacinamide', 'synergy', 'low', 'cumulative', 'Azelaic acid and niacinamide can be complementary for acne-prone or redness-prone routines.', 'This pairing is generally compatibility-positive and may support barrier tolerance.', 'PMID:40233838', '{}'::jsonb)
)
INSERT INTO interactions (
    ingredient_a_id,
    ingredient_b_id,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    confidence,
    skin_type_modifier
)
SELECT
    ingredient_a.ingridient_id,
    ingredient_b.ingridient_id,
    rule_seed.interaction_type,
    rule_seed.severity,
    rule_seed.conflict_scope,
    rule_seed.mechanism,
    rule_seed.description,
    rule_seed.source_citation,
    'provisional',
    rule_seed.skin_type_modifier
FROM rule_seed
JOIN ingredients ingredient_a ON LOWER(ingredient_a.inci_name) = LOWER(rule_seed.ingredient_a)
JOIN ingredients ingredient_b ON LOWER(ingredient_b.inci_name) = LOWER(rule_seed.ingredient_b)
ON CONFLICT DO NOTHING;

WITH followup_rule_seed (
    ingredient_a,
    ingredient_b,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    skin_type_modifier
) AS (
    VALUES
    ('Zinc Oxide', 'Retinol', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports routines using photosensitivity-associated actives.', 'Sunscreen support is compatibility-positive for routines that include retinol.', 'PMID:37169404', '{}'::jsonb),
    ('Zinc Oxide', 'Retinal', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports routines using photosensitivity-associated actives.', 'Sunscreen support is compatibility-positive for routines that include retinal.', 'PMID:37169404', '{}'::jsonb),
    ('Zinc Oxide', 'Tretinoin', 'synergy', 'medium', 'cumulative', 'Broad-spectrum sun protection supports prescription retinoid routines.', 'Sunscreen support is especially important in routines that include tretinoin.', 'PMID:37169404', '{}'::jsonb),
    ('Zinc Oxide', 'Adapalene', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports acne routines using topical retinoids.', 'Sunscreen support is compatibility-positive for routines that include adapalene.', 'PMID:38300170', '{}'::jsonb),
    ('Zinc Oxide', 'Glycolic Acid', 'synergy', 'medium', 'cumulative', 'Broad-spectrum sun protection supports routines using exfoliating acids.', 'Sunscreen support is compatibility-positive for routines that include glycolic acid.', 'PMID:37169404', '{}'::jsonb),
    ('Zinc Oxide', 'Lactic Acid', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports routines using exfoliating acids.', 'Sunscreen support is compatibility-positive for routines that include lactic acid.', 'PMID:37169404', '{}'::jsonb),
    ('Zinc Oxide', 'Salicylic Acid', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports acne routines using exfoliating acids.', 'Sunscreen support is compatibility-positive for routines that include salicylic acid.', 'PMID:38300170', '{}'::jsonb),
    ('Zinc Oxide', 'Benzoyl Peroxide', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports acne routines that may increase dryness or irritation.', 'Sunscreen support is compatibility-positive for routines that include benzoyl peroxide.', 'PMID:38300170', '{}'::jsonb),
    ('Zinc Oxide', 'Hydroquinone', 'synergy', 'medium', 'cumulative', 'Sun protection is a core support step in pigment-focused routines.', 'Sunscreen support is compatibility-positive for routines that include hydroquinone.', 'PMID:22220462', '{}'::jsonb),
    ('Zinc Oxide', 'Ascorbic Acid', 'synergy', 'low', 'cumulative', 'Antioxidant and sunscreen routines can be complementary for photoaging-focused care.', 'Sunscreen support is compatibility-positive for routines that include vitamin C.', 'PMID:37169404', '{}'::jsonb),
    ('Titanium Dioxide', 'Retinol', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports routines using photosensitivity-associated actives.', 'Sunscreen support is compatibility-positive for routines that include retinol.', 'PMID:37169404', '{}'::jsonb),
    ('Titanium Dioxide', 'Retinal', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports routines using photosensitivity-associated actives.', 'Sunscreen support is compatibility-positive for routines that include retinal.', 'PMID:37169404', '{}'::jsonb),
    ('Titanium Dioxide', 'Tretinoin', 'synergy', 'medium', 'cumulative', 'Broad-spectrum sun protection supports prescription retinoid routines.', 'Sunscreen support is especially important in routines that include tretinoin.', 'PMID:37169404', '{}'::jsonb),
    ('Titanium Dioxide', 'Adapalene', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports acne routines using topical retinoids.', 'Sunscreen support is compatibility-positive for routines that include adapalene.', 'PMID:38300170', '{}'::jsonb),
    ('Titanium Dioxide', 'Glycolic Acid', 'synergy', 'medium', 'cumulative', 'Broad-spectrum sun protection supports routines using exfoliating acids.', 'Sunscreen support is compatibility-positive for routines that include glycolic acid.', 'PMID:37169404', '{}'::jsonb),
    ('Titanium Dioxide', 'Lactic Acid', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports routines using exfoliating acids.', 'Sunscreen support is compatibility-positive for routines that include lactic acid.', 'PMID:37169404', '{}'::jsonb),
    ('Titanium Dioxide', 'Salicylic Acid', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports acne routines using exfoliating acids.', 'Sunscreen support is compatibility-positive for routines that include salicylic acid.', 'PMID:38300170', '{}'::jsonb),
    ('Titanium Dioxide', 'Benzoyl Peroxide', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports acne routines that may increase dryness or irritation.', 'Sunscreen support is compatibility-positive for routines that include benzoyl peroxide.', 'PMID:38300170', '{}'::jsonb),
    ('Titanium Dioxide', 'Hydroquinone', 'synergy', 'medium', 'cumulative', 'Sun protection is a core support step in pigment-focused routines.', 'Sunscreen support is compatibility-positive for routines that include hydroquinone.', 'PMID:22220462', '{}'::jsonb),
    ('Titanium Dioxide', 'Ascorbic Acid', 'synergy', 'low', 'cumulative', 'Antioxidant and sunscreen routines can be complementary for photoaging-focused care.', 'Sunscreen support is compatibility-positive for routines that include vitamin C.', 'PMID:37169404', '{}'::jsonb),
    ('Avobenzone', 'Retinol', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports routines using photosensitivity-associated actives.', 'Sunscreen support is compatibility-positive for routines that include retinol.', 'PMID:37169404', '{}'::jsonb),
    ('Avobenzone', 'Retinal', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports routines using photosensitivity-associated actives.', 'Sunscreen support is compatibility-positive for routines that include retinal.', 'PMID:37169404', '{}'::jsonb),
    ('Avobenzone', 'Tretinoin', 'synergy', 'medium', 'cumulative', 'Broad-spectrum sun protection supports prescription retinoid routines.', 'Sunscreen support is especially important in routines that include tretinoin.', 'PMID:37169404', '{}'::jsonb),
    ('Avobenzone', 'Adapalene', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports acne routines using topical retinoids.', 'Sunscreen support is compatibility-positive for routines that include adapalene.', 'PMID:38300170', '{}'::jsonb),
    ('Avobenzone', 'Glycolic Acid', 'synergy', 'medium', 'cumulative', 'Broad-spectrum sun protection supports routines using exfoliating acids.', 'Sunscreen support is compatibility-positive for routines that include glycolic acid.', 'PMID:37169404', '{}'::jsonb),
    ('Avobenzone', 'Lactic Acid', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports routines using exfoliating acids.', 'Sunscreen support is compatibility-positive for routines that include lactic acid.', 'PMID:37169404', '{}'::jsonb),
    ('Avobenzone', 'Salicylic Acid', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports acne routines using exfoliating acids.', 'Sunscreen support is compatibility-positive for routines that include salicylic acid.', 'PMID:38300170', '{}'::jsonb),
    ('Avobenzone', 'Benzoyl Peroxide', 'synergy', 'low', 'cumulative', 'Broad-spectrum sun protection supports acne routines that may increase dryness or irritation.', 'Sunscreen support is compatibility-positive for routines that include benzoyl peroxide.', 'PMID:38300170', '{}'::jsonb),
    ('Avobenzone', 'Hydroquinone', 'synergy', 'medium', 'cumulative', 'Sun protection is a core support step in pigment-focused routines.', 'Sunscreen support is compatibility-positive for routines that include hydroquinone.', 'PMID:22220462', '{}'::jsonb),
    ('Avobenzone', 'Ascorbic Acid', 'synergy', 'low', 'cumulative', 'Antioxidant and sunscreen routines can be complementary for photoaging-focused care.', 'Sunscreen support is compatibility-positive for routines that include vitamin C.', 'PMID:37169404', '{}'::jsonb),
    ('Ceramide NP', 'Retinol', 'synergy', 'low', 'cumulative', 'Barrier-support moisturizers can improve tolerability in active-heavy routines.', 'Ceramide support can be helpful in routines that include retinol.', 'PMID:24847408', '{}'::jsonb),
    ('Ceramide NP', 'Tretinoin', 'synergy', 'medium', 'cumulative', 'Barrier-support moisturizers can improve tolerability in retinoid routines.', 'Ceramide support can be helpful in routines that include tretinoin.', 'PMID:24847408', '{}'::jsonb),
    ('Ceramide NP', 'Benzoyl Peroxide', 'synergy', 'low', 'cumulative', 'Barrier-support moisturizers can improve tolerability in acne-active routines.', 'Ceramide support can be helpful in routines that include benzoyl peroxide.', 'PMID:24847408', '{}'::jsonb),
    ('Ceramide NP', 'Glycolic Acid', 'synergy', 'low', 'cumulative', 'Barrier-support moisturizers can improve tolerability in exfoliating-acid routines.', 'Ceramide support can be helpful in routines that include glycolic acid.', 'PMID:24847408', '{}'::jsonb),
    ('Ceramide NP', 'Salicylic Acid', 'synergy', 'low', 'cumulative', 'Barrier-support moisturizers can improve tolerability in exfoliating-acid routines.', 'Ceramide support can be helpful in routines that include salicylic acid.', 'PMID:24847408', '{}'::jsonb),
    ('Ceramide AP', 'Retinol', 'synergy', 'low', 'cumulative', 'Barrier-support moisturizers can improve tolerability in active-heavy routines.', 'Ceramide support can be helpful in routines that include retinol.', 'PMID:24847408', '{}'::jsonb),
    ('Ceramide AP', 'Tretinoin', 'synergy', 'medium', 'cumulative', 'Barrier-support moisturizers can improve tolerability in retinoid routines.', 'Ceramide support can be helpful in routines that include tretinoin.', 'PMID:24847408', '{}'::jsonb),
    ('Ceramide AP', 'Benzoyl Peroxide', 'synergy', 'low', 'cumulative', 'Barrier-support moisturizers can improve tolerability in acne-active routines.', 'Ceramide support can be helpful in routines that include benzoyl peroxide.', 'PMID:24847408', '{}'::jsonb),
    ('Ceramide AP', 'Glycolic Acid', 'synergy', 'low', 'cumulative', 'Barrier-support moisturizers can improve tolerability in exfoliating-acid routines.', 'Ceramide support can be helpful in routines that include glycolic acid.', 'PMID:24847408', '{}'::jsonb),
    ('Ceramide AP', 'Salicylic Acid', 'synergy', 'low', 'cumulative', 'Barrier-support moisturizers can improve tolerability in exfoliating-acid routines.', 'Ceramide support can be helpful in routines that include salicylic acid.', 'PMID:24847408', '{}'::jsonb),
    ('Hyaluronic Acid', 'Retinol', 'synergy', 'low', 'cumulative', 'Hydrating ingredients can support tolerability in retinoid routines.', 'Hyaluronic acid can be useful support in routines that include retinol.', 'PMID:24847408', '{}'::jsonb),
    ('Hyaluronic Acid', 'Tretinoin', 'synergy', 'low', 'cumulative', 'Hydrating ingredients can support tolerability in retinoid routines.', 'Hyaluronic acid can be useful support in routines that include tretinoin.', 'PMID:24847408', '{}'::jsonb),
    ('Hyaluronic Acid', 'Benzoyl Peroxide', 'synergy', 'low', 'cumulative', 'Hydrating ingredients can support tolerability in acne-active routines.', 'Hyaluronic acid can be useful support in routines that include benzoyl peroxide.', 'PMID:24847408', '{}'::jsonb),
    ('Hyaluronic Acid', 'Glycolic Acid', 'synergy', 'low', 'cumulative', 'Hydrating ingredients can support tolerability in exfoliating-acid routines.', 'Hyaluronic acid can be useful support in routines that include glycolic acid.', 'PMID:24847408', '{}'::jsonb),
    ('Hyaluronic Acid', 'Salicylic Acid', 'synergy', 'low', 'cumulative', 'Hydrating ingredients can support tolerability in exfoliating-acid routines.', 'Hyaluronic acid can be useful support in routines that include salicylic acid.', 'PMID:24847408', '{}'::jsonb),
    ('Panthenol', 'Retinol', 'synergy', 'low', 'cumulative', 'Soothing barrier-support ingredients can improve tolerability in retinoid routines.', 'Panthenol can be useful support in routines that include retinol.', 'PMID:24847408', '{}'::jsonb),
    ('Panthenol', 'Tretinoin', 'synergy', 'low', 'cumulative', 'Soothing barrier-support ingredients can improve tolerability in retinoid routines.', 'Panthenol can be useful support in routines that include tretinoin.', 'PMID:24847408', '{}'::jsonb),
    ('Panthenol', 'Benzoyl Peroxide', 'synergy', 'low', 'cumulative', 'Soothing barrier-support ingredients can improve tolerability in acne-active routines.', 'Panthenol can be useful support in routines that include benzoyl peroxide.', 'PMID:24847408', '{}'::jsonb),
    ('Panthenol', 'Glycolic Acid', 'synergy', 'low', 'cumulative', 'Soothing barrier-support ingredients can improve tolerability in exfoliating-acid routines.', 'Panthenol can be useful support in routines that include glycolic acid.', 'PMID:24847408', '{}'::jsonb),
    ('Panthenol', 'Salicylic Acid', 'synergy', 'low', 'cumulative', 'Soothing barrier-support ingredients can improve tolerability in exfoliating-acid routines.', 'Panthenol can be useful support in routines that include salicylic acid.', 'PMID:24847408', '{}'::jsonb)
)
INSERT INTO interactions (
    ingredient_a_id,
    ingredient_b_id,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    confidence,
    skin_type_modifier
)
SELECT
    ingredient_a.ingridient_id,
    ingredient_b.ingridient_id,
    followup_rule_seed.interaction_type,
    followup_rule_seed.severity,
    followup_rule_seed.conflict_scope,
    followup_rule_seed.mechanism,
    followup_rule_seed.description,
    followup_rule_seed.source_citation,
    'provisional',
    followup_rule_seed.skin_type_modifier
FROM followup_rule_seed
JOIN ingredients ingredient_a ON LOWER(ingredient_a.inci_name) = LOWER(followup_rule_seed.ingredient_a)
JOIN ingredients ingredient_b ON LOWER(ingredient_b.inci_name) = LOWER(followup_rule_seed.ingredient_b)
ON CONFLICT DO NOTHING;

WITH third_rule_seed (
    ingredient_a,
    ingredient_b,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    skin_type_modifier
) AS (
    VALUES
    ('Retinol', 'Citric Acid', 'caution', 'medium', 'both', 'Retinoids and exfoliating acids can compound irritation.', 'Retinol with citric acid may increase dryness or stinging in active-heavy routines.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinol', 'Malic Acid', 'caution', 'medium', 'both', 'Retinoids and exfoliating acids can compound irritation.', 'Retinol with malic acid should be introduced gradually.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinol', 'Tartaric Acid', 'caution', 'medium', 'both', 'Retinoids and exfoliating acids can compound irritation.', 'Retinol with tartaric acid may be irritating if used too frequently.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinal', 'Mandelic Acid', 'caution', 'medium', 'both', 'Retinoids and alpha hydroxy acids can increase irritation.', 'Retinal with mandelic acid should be introduced slowly.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinal', 'Citric Acid', 'caution', 'medium', 'both', 'Retinoids and exfoliating acids can compound irritation.', 'Retinal with citric acid may increase dryness or stinging.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinal', 'Malic Acid', 'caution', 'medium', 'both', 'Retinoids and exfoliating acids can compound irritation.', 'Retinal with malic acid should be used cautiously in sensitive routines.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinal', 'Tartaric Acid', 'caution', 'medium', 'both', 'Retinoids and exfoliating acids can compound irritation.', 'Retinal with tartaric acid can add to irritation load.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinal', 'Betaine Salicylate', 'caution', 'medium', 'both', 'Retinoids and salicylate exfoliants may compound dryness.', 'Retinal with betaine salicylate should be introduced gradually.', 'PMID:26516077', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Retinal', 'Gluconolactone', 'caution', 'low', 'both', 'Retinoids and exfoliating acids may increase irritation in sensitive skin.', 'Retinal with gluconolactone is lower risk but can still add to active load.', 'PMID:32356369', '{"sensitive": "medium", "dry": "medium"}'::jsonb),
    ('Retinal', 'Lactobionic Acid', 'caution', 'low', 'both', 'Retinoids and exfoliating acids may increase irritation in sensitive skin.', 'Retinal with lactobionic acid is lower risk but should still be introduced gradually.', 'PMID:32356369', '{"sensitive": "medium", "dry": "medium"}'::jsonb),
    ('Tretinoin', 'Mandelic Acid', 'caution', 'high', 'both', 'Prescription-strength retinoids and exfoliating acids can compound irritation.', 'Tretinoin with mandelic acid may be too irritating if started together.', 'PMID:33377285', '{"sensitive": "high", "dry": "high", "normal": "medium"}'::jsonb),
    ('Tretinoin', 'Citric Acid', 'caution', 'high', 'both', 'Prescription-strength retinoids and exfoliating acids can compound irritation.', 'Tretinoin with citric acid can increase dryness and stinging.', 'PMID:33377285', '{"sensitive": "high", "dry": "high", "normal": "medium"}'::jsonb),
    ('Tretinoin', 'Malic Acid', 'caution', 'high', 'both', 'Prescription-strength retinoids and exfoliating acids can compound irritation.', 'Tretinoin with malic acid should be handled cautiously.', 'PMID:33377285', '{"sensitive": "high", "dry": "high", "normal": "medium"}'::jsonb),
    ('Tretinoin', 'Tartaric Acid', 'caution', 'high', 'both', 'Prescription-strength retinoids and exfoliating acids can compound irritation.', 'Tretinoin with tartaric acid can be harsh in frequent routines.', 'PMID:33377285', '{"sensitive": "high", "dry": "high", "normal": "medium"}'::jsonb),
    ('Tretinoin', 'Betaine Salicylate', 'caution', 'high', 'both', 'Prescription-strength retinoids and salicylate exfoliants can compound irritation.', 'Tretinoin with betaine salicylate may increase dryness or peeling.', 'PMID:26516077', '{"sensitive": "high", "dry": "high", "normal": "medium"}'::jsonb),
    ('Tretinoin', 'Gluconolactone', 'caution', 'medium', 'both', 'Prescription-strength retinoids and exfoliating acids can add to irritation load.', 'Tretinoin with gluconolactone should be introduced gradually.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Tretinoin', 'Lactobionic Acid', 'caution', 'medium', 'both', 'Prescription-strength retinoids and exfoliating acids can add to irritation load.', 'Tretinoin with lactobionic acid should be introduced gradually.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Adapalene', 'Mandelic Acid', 'caution', 'medium', 'both', 'Topical retinoids and alpha hydroxy acids can increase irritation.', 'Adapalene with mandelic acid should be introduced slowly.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Adapalene', 'Citric Acid', 'caution', 'medium', 'both', 'Topical retinoids and exfoliating acids can increase irritation.', 'Adapalene with citric acid may add to dryness or stinging.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Adapalene', 'Malic Acid', 'caution', 'medium', 'both', 'Topical retinoids and exfoliating acids can increase irritation.', 'Adapalene with malic acid should be used cautiously in sensitive routines.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Adapalene', 'Tartaric Acid', 'caution', 'medium', 'both', 'Topical retinoids and exfoliating acids can increase irritation.', 'Adapalene with tartaric acid can add to active irritation load.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Adapalene', 'Betaine Salicylate', 'caution', 'medium', 'both', 'Topical retinoids and salicylate exfoliants may compound dryness.', 'Adapalene with betaine salicylate should be introduced gradually.', 'PMID:26516077', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Adapalene', 'Gluconolactone', 'caution', 'low', 'both', 'Topical retinoids and exfoliating acids can add to irritation load.', 'Adapalene with gluconolactone is lower risk but still worth spacing out in sensitive routines.', 'PMID:32356369', '{"sensitive": "medium"}'::jsonb),
    ('Adapalene', 'Lactobionic Acid', 'caution', 'low', 'both', 'Topical retinoids and exfoliating acids can add to irritation load.', 'Adapalene with lactobionic acid is lower risk but still worth spacing out in sensitive routines.', 'PMID:32356369', '{"sensitive": "medium"}'::jsonb),
    ('Benzoyl Peroxide', 'Lactic Acid', 'caution', 'high', 'both', 'Combining antibacterial acne actives with exfoliating acids can increase irritation.', 'Benzoyl peroxide with lactic acid may be too harsh when layered directly or used daily.', 'PMID:32356369', '{"sensitive": "high", "dry": "high", "normal": "medium"}'::jsonb),
    ('Benzoyl Peroxide', 'Mandelic Acid', 'caution', 'medium', 'both', 'Combining antibacterial acne actives with exfoliating acids can increase irritation.', 'Benzoyl peroxide with mandelic acid should be introduced gradually.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Benzoyl Peroxide', 'Citric Acid', 'caution', 'medium', 'both', 'Combining antibacterial acne actives with exfoliating acids can increase irritation.', 'Benzoyl peroxide with citric acid can add dryness or stinging.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Benzoyl Peroxide', 'Malic Acid', 'caution', 'medium', 'both', 'Combining antibacterial acne actives with exfoliating acids can increase irritation.', 'Benzoyl peroxide with malic acid should be used cautiously.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Benzoyl Peroxide', 'Tartaric Acid', 'caution', 'medium', 'both', 'Combining antibacterial acne actives with exfoliating acids can increase irritation.', 'Benzoyl peroxide with tartaric acid can be harsh in frequent routines.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Benzoyl Peroxide', 'Betaine Salicylate', 'caution', 'high', 'both', 'Combining antibacterial acne actives with salicylate exfoliants can increase irritation.', 'Benzoyl peroxide with betaine salicylate may compound dryness and peeling.', 'PMID:32356369', '{"sensitive": "high", "dry": "high", "normal": "medium"}'::jsonb),
    ('Benzoyl Peroxide', 'Gluconolactone', 'caution', 'medium', 'both', 'Combining antibacterial acne actives with exfoliating acids can increase irritation.', 'Benzoyl peroxide with gluconolactone can still add to active irritation load.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Benzoyl Peroxide', 'Lactobionic Acid', 'caution', 'medium', 'both', 'Combining antibacterial acne actives with exfoliating acids can increase irritation.', 'Benzoyl peroxide with lactobionic acid can still add to active irritation load.', 'PMID:32356369', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Ascorbic Acid', 'Citric Acid', 'caution', 'medium', 'direct', 'Layering low-pH vitamin C with acids can increase stinging and irritation.', 'Ascorbic acid with citric acid should be introduced gradually.', 'PMID:35642229', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Ascorbic Acid', 'Malic Acid', 'caution', 'medium', 'direct', 'Layering low-pH vitamin C with acids can increase stinging and irritation.', 'Ascorbic acid with malic acid should be used cautiously in sensitive routines.', 'PMID:35642229', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Ascorbic Acid', 'Tartaric Acid', 'caution', 'medium', 'direct', 'Layering low-pH vitamin C with acids can increase stinging and irritation.', 'Ascorbic acid with tartaric acid may add to acid irritation load.', 'PMID:35642229', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Ascorbic Acid', 'Gluconolactone', 'caution', 'low', 'direct', 'Vitamin C and mild exfoliating acids can add to irritation load.', 'Ascorbic acid with gluconolactone is lower risk but can still sting sensitive skin.', 'PMID:35642229', '{"sensitive": "medium"}'::jsonb),
    ('Ascorbic Acid', 'Lactobionic Acid', 'caution', 'low', 'direct', 'Vitamin C and mild exfoliating acids can add to irritation load.', 'Ascorbic acid with lactobionic acid is lower risk but can still sting sensitive skin.', 'PMID:35642229', '{"sensitive": "medium"}'::jsonb),
    ('Ascorbic Acid', 'Betaine Salicylate', 'caution', 'medium', 'direct', 'Low-pH vitamin C and salicylate exfoliants can compound irritation.', 'Ascorbic acid with betaine salicylate should be introduced gradually.', 'PMID:35642229', '{"sensitive": "high", "dry": "high"}'::jsonb),
    ('Sodium Ascorbyl Phosphate', 'Retinol', 'synergy', 'low', 'cumulative', 'Vitamin C derivatives and retinoids can be complementary in tone and photoaging routines.', 'This pairing may support brightening and renewal goals without being a direct conflict.', 'PMID:37169404', '{}'::jsonb),
    ('Ascorbyl Glucoside', 'Retinol', 'synergy', 'low', 'cumulative', 'Vitamin C derivatives and retinoids can be complementary in tone and photoaging routines.', 'This pairing may support brightening and renewal goals without being a direct conflict.', 'PMID:37169404', '{}'::jsonb),
    ('Zinc Oxide', 'Kojic Acid', 'synergy', 'medium', 'cumulative', 'Sun protection is a core support step in pigment-focused routines.', 'Sunscreen support is compatibility-positive for routines that include kojic acid.', 'PMID:22220462', '{}'::jsonb),
    ('Zinc Oxide', 'Alpha Arbutin', 'synergy', 'medium', 'cumulative', 'Sun protection is a core support step in pigment-focused routines.', 'Sunscreen support is compatibility-positive for routines that include alpha arbutin.', 'PMID:22220462', '{}'::jsonb),
    ('Zinc Oxide', 'Tranexamic Acid', 'synergy', 'medium', 'cumulative', 'Sun protection is a core support step in pigment-focused routines.', 'Sunscreen support is compatibility-positive for routines that include tranexamic acid.', 'PMID:22220462', '{}'::jsonb),
    ('Zinc Oxide', 'Azelaic Acid', 'synergy', 'medium', 'cumulative', 'Sun protection supports acne and pigment routines that include azelaic acid.', 'Sunscreen support is compatibility-positive for routines that include azelaic acid.', 'PMID:35642229', '{}'::jsonb),
    ('Titanium Dioxide', 'Kojic Acid', 'synergy', 'medium', 'cumulative', 'Sun protection is a core support step in pigment-focused routines.', 'Sunscreen support is compatibility-positive for routines that include kojic acid.', 'PMID:22220462', '{}'::jsonb),
    ('Titanium Dioxide', 'Alpha Arbutin', 'synergy', 'medium', 'cumulative', 'Sun protection is a core support step in pigment-focused routines.', 'Sunscreen support is compatibility-positive for routines that include alpha arbutin.', 'PMID:22220462', '{}'::jsonb),
    ('Titanium Dioxide', 'Tranexamic Acid', 'synergy', 'medium', 'cumulative', 'Sun protection is a core support step in pigment-focused routines.', 'Sunscreen support is compatibility-positive for routines that include tranexamic acid.', 'PMID:22220462', '{}'::jsonb),
    ('Titanium Dioxide', 'Azelaic Acid', 'synergy', 'medium', 'cumulative', 'Sun protection supports acne and pigment routines that include azelaic acid.', 'Sunscreen support is compatibility-positive for routines that include azelaic acid.', 'PMID:35642229', '{}'::jsonb),
    ('Avobenzone', 'Kojic Acid', 'synergy', 'medium', 'cumulative', 'Sun protection is a core support step in pigment-focused routines.', 'Sunscreen support is compatibility-positive for routines that include kojic acid.', 'PMID:22220462', '{}'::jsonb),
    ('Avobenzone', 'Tranexamic Acid', 'synergy', 'medium', 'cumulative', 'Sun protection is a core support step in pigment-focused routines.', 'Sunscreen support is compatibility-positive for routines that include tranexamic acid.', 'PMID:22220462', '{}'::jsonb)
)
INSERT INTO interactions (
    ingredient_a_id,
    ingredient_b_id,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    confidence,
    skin_type_modifier
)
SELECT
    ingredient_a.ingridient_id,
    ingredient_b.ingridient_id,
    third_rule_seed.interaction_type,
    third_rule_seed.severity,
    third_rule_seed.conflict_scope,
    third_rule_seed.mechanism,
    third_rule_seed.description,
    third_rule_seed.source_citation,
    'provisional',
    third_rule_seed.skin_type_modifier
FROM third_rule_seed
JOIN ingredients ingredient_a ON LOWER(ingredient_a.inci_name) = LOWER(third_rule_seed.ingredient_a)
JOIN ingredients ingredient_b ON LOWER(ingredient_b.inci_name) = LOWER(third_rule_seed.ingredient_b)
ON CONFLICT DO NOTHING;

WITH source_updates (ingredient_a, ingredient_b, source_citation) AS (
    VALUES
    ('Retinol', 'Glycolic Acid', 'PMID:33377285'),
    ('Benzoyl Peroxide', 'Retinol', 'PMID:38300170'),
    ('Ascorbic Acid', 'Glycolic Acid', 'PMID:35642229'),
    ('Ascorbic Acid', 'Retinol', 'PMID:37169404'),
    ('Niacinamide', 'Glycolic Acid', 'PMID:40233838')
)
UPDATE interactions interaction
SET source_citation = source_updates.source_citation,
    updated_at = NOW()
FROM source_updates
JOIN ingredients ingredient_a ON LOWER(ingredient_a.inci_name) = LOWER(source_updates.ingredient_a)
JOIN ingredients ingredient_b ON LOWER(ingredient_b.inci_name) = LOWER(source_updates.ingredient_b)
WHERE LEAST(interaction.ingredient_a_id, interaction.ingredient_b_id) = LEAST(ingredient_a.ingridient_id, ingredient_b.ingridient_id)
  AND GREATEST(interaction.ingredient_a_id, interaction.ingredient_b_id) = GREATEST(ingredient_a.ingridient_id, ingredient_b.ingridient_id)
  AND interaction.source_citation NOT LIKE 'PMID:%';

UPDATE interaction_gaps gap
SET status = 'published',
    last_seen = NOW()
FROM interactions interaction
WHERE LEAST(gap.ingredient_a_id, gap.ingredient_b_id) = LEAST(interaction.ingredient_a_id, interaction.ingredient_b_id)
  AND GREATEST(gap.ingredient_a_id, gap.ingredient_b_id) = GREATEST(interaction.ingredient_a_id, interaction.ingredient_b_id);