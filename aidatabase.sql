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
    parsed_ingredient_ids INTEGER[] NOT NULL DEFAULT '{}',
    source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'open_beauty_facts', 'user_submitted')),
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS skin_profiles (
    skin_profile_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_label TEXT NOT NULL DEFAULT 'demo',
    skin_type TEXT NOT NULL CHECK (skin_type IN ('oily', 'dry', 'combination', 'sensitive', 'normal')),
    concerns TEXT[] NOT NULL DEFAULT '{}',
    known_irritant_ids INTEGER[] NOT NULL DEFAULT '{}',
    current_active_ids INTEGER[] NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS routines (
    routine_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    skin_profile_id INTEGER REFERENCES skin_profiles(skin_profile_id) ON DELETE SET NULL,
    time_of_day TEXT NOT NULL CHECK (time_of_day IN ('am', 'pm')),
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS routine_products (
    routine_product_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    routine_id INTEGER NOT NULL REFERENCES routines(routine_id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    step_order INTEGER NOT NULL,
    frequency TEXT NOT NULL DEFAULT 'daily' CHECK (frequency IN ('daily', 'alternating', 'weekly')),
    days_of_week TEXT[] NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (routine_id, step_order)
);

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
    'Advisor review required before production use',
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
    'Advisor review required before production use',
    'provisional',
    '{"sensitive": "high", "dry": "high"}'::jsonb
FROM benzoyl, retinol
ON CONFLICT DO NOTHING;