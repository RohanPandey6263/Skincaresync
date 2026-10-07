-- SkincareSync: the whole migration chain in one file.
--
-- GENERATED — do not edit. Run scripts/build_install_sql.sh to rebuild it from
-- aidatabase.sql and migrations/0*.sql.
--
-- Every step is idempotent, so this is safe to re-run against a database that
-- is already partly or fully migrated. Each migration keeps its own
-- BEGIN/COMMIT, so a failure rolls back that step, not the ones before it.
--
-- Self-contained: migration 000 creates and seeds `ingredients`, so this runs
-- against a completely empty database as well as one that is already partly
-- or fully migrated.
--
--     psql -d "$PGDATABASE" -f migrations/install.sql
--
-- Contents, in order:
--   migrations/000_ingredients.sql
--   aidatabase.sql
--   migrations/002_ingredient_catalog.sql
--   migrations/003_ingredient_search_alias.sql
--   migrations/004_product_catalog.sql
--   migrations/005_product_variants_and_search_indexes.sql
--   migrations/006_drop_unused_schema.sql
--   migrations/007_auth.sql
--   migrations/008_social_identities.sql
--   migrations/009_catalog_interactions.sql
--   migrations/010_tretinoin_interactions.sql

\set ON_ERROR_STOP on


-- ======================================================================
-- migrations/000_ingredients.sql
-- ======================================================================

-- SkincareSync migration 000: the `ingredients` table and its curated rows.
--
-- Every later migration extends this table in place rather than creating it,
-- and every seeded interaction rule resolves its two ingredients by joining
-- against it. Without this file a fresh database gets the tables but none of
-- the rules: the seed INSERTs in aidatabase.sql, 009 and 010 all inner-join
-- `ingredients`, so on an empty catalog they match nothing and quietly insert
-- zero rows. This migration is what makes the chain self-contained.
--
-- Scope: the base columns only. Migration 002 adds the catalog columns
-- (alt_names, functions, descriptions, identifiers) and the search
-- infrastructure, and `scripts/import_ingredient_catalog.py` fills those in
-- from the Open Beauty Facts taxonomy. What is seeded here is the curated
-- layer that the interaction rules depend on and that no importer reproduces:
-- the canonical name, curated synonyms, category, pH range and comedogenic
-- rating for 141 ingredients.
--
-- Idempotent: safe to re-run, and a no-op on a database that already has the
-- table (CREATE TABLE IF NOT EXISTS) or already has these rows
-- (ON CONFLICT DO NOTHING). It will not overwrite curated values that have
-- since been edited by hand.

BEGIN;

-- `ingridient_id` is misspelled. It is the real column name, referenced by
-- foreign keys in `interactions`, `parser_unknowns` and `interaction_gaps` and
-- by every query in `skincaresync/`; renaming it is a separate migration with
-- a code change attached, not a detail to fix silently here.
--
-- inci_name is TEXT rather than the varchar(500) the original table used:
-- migration 002 widens it anyway (multi-botanical ferment names run to ~1,900
-- characters), and starting wide skips a full table rewrite on a fresh install.
CREATE TABLE IF NOT EXISTS ingredients (
    ingridient_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inci_name TEXT NOT NULL UNIQUE,
    synonyms TEXT[],
    category TEXT,
    ph_min DOUBLE PRECISION,
    ph_max DOUBLE PRECISION,
    comodogenic INTEGER,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT NOW()
);

-- Curated catalog. Names are trimmed: 20 sunscreen rows in the original
-- development database carried leading and trailing spaces on inci_name,
-- category and every synonym, which breaks the `LOWER(inci_name) = '...'`
-- joins the rule seeds use. The generated `normalized_name` column added in
-- 002 trims anyway, so the runtime resolver never noticed.
INSERT INTO ingredients (inci_name, synonyms, category, ph_min, ph_max, comodogenic)
VALUES
    ('Adapalene', '{Differin,CD271}'::text[], 'retinoid', 5.5, 7, 0),
    ('Allantoin', '{"Aluminum Dihydroxy Allantoinate",5-Ureidohydantoin}'::text[], 'soothing', 5, 7, 0),
    ('Aloe Vera', '{"Aloe Barbadensis Leaf Juice",Aloe}'::text[], 'botanical', NULL, NULL, 0),
    ('Alpha Arbutin', '{Arbutin,"Hydroquinone Beta-D-Glucopyranoside"}'::text[], 'brightening', 5, 7, 0),
    ('Amiloxate', '{"Isopentyl 4 - Methoxycinnamate",IMC}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Amodimethicone', '{"Amino Silicone"}'::text[], 'silicone', NULL, NULL, 0),
    ('Argan Oil', '{"Argania Spinosa Kernel Oil"}'::text[], 'botanical', NULL, NULL, 0),
    ('Argireline', '{"Acetyl Hexapeptide-3","Acetyl Hexapeptide-8"}'::text[], 'peptide', 5, 7, 0),
    ('Ascorbic Acid', '{"Vitamin C","L-Ascorbic Acid",Ascorbate}'::text[], 'antioxidant', 2.5, 3.5, 0),
    ('Ascorbyl Glucoside', '{AA2G,"Vitamin C Glucoside"}'::text[], 'antioxidant', 5, 7, 0),
    ('Avobenzone', '{"Butyl Methoxydibenzoylmethane","Parsol 1789"}'::text[], 'sunscreen', NULL, NULL, 0),
    ('Azelaic Acid', '{"Nonanedioic Acid",Finacea}'::text[], 'brightening', 4, 5.5, 0),
    ('Bakuchiol', '{"Psoralea Corylifolia Extract","Plant Retinol Alternative"}'::text[], 'botanical', NULL, NULL, 0),
    ('Bemotrizinol', '{"Tinosorb S",BEMT}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Benzalkonium Chloride', '{BAC,Zephiran}'::text[], 'preservative', NULL, NULL, 0),
    ('Benzoyl Peroxide', '{BPO,"Dibenzoyl Peroxide"}'::text[], 'antibacterial', 4, 6, 0),
    ('Benzyl Alcohol', '{Phenylmethanol,Benzenemethanol}'::text[], 'fragrance', NULL, NULL, 0),
    ('Beta-Glucan', '{"Oat Beta Glucan","Yeast Beta Glucan"}'::text[], 'soothing', 5, 7, 0),
    ('Betaine Salicylate', '{"Willow Bark Extract"}'::text[], 'bha', 4, 5, 0),
    ('Bisabolol', '{"Alpha Bisabolol",Levomenol,"Chamomile Extract"}'::text[], 'soothing', 5, 7, 0),
    ('Bromelain', '{"Pineapple Enzyme","Ananas Comosus Extract"}'::text[], 'enzyme', 5.5, 7, 0),
    ('Butylparaben', '{"Butyl 4-hydroxybenzoate",Paraben}'::text[], 'preservative', NULL, NULL, 0),
    ('Calendula Extract', '{"Calendula Officinalis Flower Extract","Marigold Extract"}'::text[], 'botanical', NULL, NULL, 0),
    ('Castor Oil', '{"Ricinus Communis Seed Oil"}'::text[], 'oil', NULL, NULL, 1),
    ('Centella Asiatica Extract', '{Cica,"Gotu Kola",TECA,Madecassoside}'::text[], 'soothing', 5, 7, 0),
    ('Ceramide AP', '{"Ceramide 6 II","Alpha-hydroxy Ceramide"}'::text[], 'emollient', 5, 7, 0),
    ('Ceramide NP', '{"Ceramide 3","N-(hexadecanoyl) sphinganine"}'::text[], 'emollient', 5, 7, 0),
    ('Chamomile Extract', '{"Matricaria Recutita Extract","Anthemis Nobilis"}'::text[], 'botanical', NULL, NULL, 0),
    ('Chlorphenesin', '{"3-(4-Chlorophenoxy)-1,2-propanediol"}'::text[], 'preservative', NULL, NULL, 0),
    ('Cinnamal', '{Cinnamaldehyde,"Cinnamic Aldehyde"}'::text[], 'fragrance', NULL, NULL, 0),
    ('Citric Acid', '{Citrate,E330}'::text[], 'aha', 3, 4, 0),
    ('Citronellol', '{Dihydrogeraniol}'::text[], 'fragrance', NULL, NULL, 0),
    ('Clindamycin', '{"Clindamycin Phosphate",Cleocin}'::text[], 'antibacterial', 5, 7, 0),
    ('Coconut Oil', '{"Cocos Nucifera Oil"}'::text[], 'oil', NULL, NULL, 4),
    ('Copper Peptide GHK-Cu', '{"Copper Tripeptide-1","GHK Copper"}'::text[], 'peptide', 6, 7, 0),
    ('Coumarin', '{"1,2-Benzopyrone","Tonka Bean Extract"}'::text[], 'fragrance', NULL, NULL, 0),
    ('Cyclohexasiloxane', '{"D6 Silicone"}'::text[], 'silicone', NULL, NULL, 0),
    ('Cyclomethicone', '{Cyclopentasiloxane,D5,"Volatile Silicone"}'::text[], 'silicone', NULL, NULL, 0),
    ('Cyclopentasiloxane', '{"D5 Silicone",Cyclomethicone}'::text[], 'silicone', NULL, NULL, 0),
    ('Dehydroacetic Acid', '{DHA,Methylacetopyranone}'::text[], 'preservative', NULL, NULL, 0),
    ('Deoxyarbutin', '{D-Arbutin,"4-[(tetrahydro-2H-pyran-2-yl)oxy] phenol"}'::text[], 'skin_tone_risk', 5, 7, 0),
    ('Diazolidinyl Urea', '{"Germall II","Formaldehyde Releaser"}'::text[], 'preservative', NULL, NULL, 0),
    ('Dimethicone', '{Polydimethylsiloxane,PDMS,Silicone}'::text[], 'silicone', NULL, NULL, 1),
    ('DMDM Hydantoin', '{"Dimethylol Dimethyl Hydantoin","Formaldehyde Releaser"}'::text[], 'preservative', NULL, NULL, 0),
    ('Ectoin', '{"Tetrahydropyrimidinecarboxylic Acid"}'::text[], 'soothing', 5, 7, 0),
    ('Ensulizole', '{"Phenylbenzimidazole Sulfonic Acid",PBSA}'::text[], 'sunscreen', NULL, NULL, 0),
    ('Enzacamene', '{"4 - Methylbenzylidene Camphor","4 - MBC"}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Ethylparaben', '{"Ethyl 4-hydroxybenzoate",Paraben}'::text[], 'preservative', NULL, NULL, 0),
    ('Eugenol', '{"Clove Oil","Clove Extract"}'::text[], 'fragrance', NULL, NULL, 0),
    ('Ferulic Acid', '{"4-Hydroxy-3-methoxycinnamic acid"}'::text[], 'botanical', 3, 4, 0),
    ('Fragrance', '{Parfum,"Fragrance Mix",Scent}'::text[], 'fragrance', NULL, NULL, 0),
    ('Geraniol', '{"Geranyl Alcohol"}'::text[], 'fragrance', NULL, NULL, 0),
    ('Gluconolactone', '{PHA,"Glucono Delta Lactone",GDL}'::text[], 'pha', 3.5, 5, 0),
    ('Glycerin', '{Glycerol,Glycerine,"1,2,3-Propanetriol"}'::text[], 'humectant', 4, 8, 0),
    ('Glycolic Acid', '{"Hydroxyacetic Acid",GA}'::text[], 'aha', 3, 4, 0),
    ('Green Tea Extract', '{"Camellia Sinensis Leaf Extract",EGCG}'::text[], 'botanical', NULL, NULL, 0),
    ('Hemp Seed Oil', '{"Cannabis Sativa Seed Oil"}'::text[], 'oil', NULL, NULL, 0),
    ('High Concentration Niacinamide', '{"Niacinamide 10%","Niacinamide 15%","Vitamin B3 High Dose"}'::text[], 'skin_tone_risk', 5, 7, 0),
    ('Homosalate', '{"Homomenthyl Salicylate",HMS}'::text[], 'sunscreen', NULL, NULL, 0),
    ('Hyaluronic Acid', '{HA,Hyaluronan,"Sodium Hyaluronate"}'::text[], 'humectant', 5, 7, 0),
    ('Hydroquinone', '{HQ,"1,4-Benzenediol",Quinol}'::text[], 'brightening', 3, 4, 0),
    ('Hydroquinone 4%', '{HQ4,"Prescription Hydroquinone"}'::text[], 'skin_tone_risk', 3, 4, 0),
    ('Imidazolidinyl Urea', '{"Germall 115","Formaldehyde Releaser"}'::text[], 'preservative', NULL, NULL, 0),
    ('Iscotrizinol', '{DIOT,"Diethylhexyl Butamido Triazone"}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Jojoba Oil', '{"Simmondsia Chinensis Seed Oil"}'::text[], 'botanical', NULL, NULL, 2),
    ('Kojic Acid', '{"Kojic Dipalmitate",5-Hydroxy-2-hydroxymethyl-4H-pyran-4-one}'::text[], 'brightening', 3.5, 5.5, 0),
    ('Kojic Acid Dipalmitate', '{"Kojic Dipalmitate","Oil Soluble Kojic"}'::text[], 'skin_tone_risk', NULL, NULL, 0),
    ('Lactic Acid', '{"L-Lactic Acid","Milk Acid"}'::text[], 'aha', 3.5, 4.5, 0),
    ('Lactobionic Acid', '{PHA,"Galactosyl Gluconic Acid"}'::text[], 'pha', 3.5, 5, 0),
    ('Licorice Root Extract', '{"Glycyrrhiza Glabra",Glabridin,"Licorice Extract"}'::text[], 'brightening', 5, 7, 0),
    ('Limonene', '{D-Limonene,"Citrus Extract"}'::text[], 'fragrance', NULL, NULL, 0),
    ('Linalool', '{"Linalyl Alcohol","3,7-Dimethyl-1,6-octadien-3-ol"}'::text[], 'fragrance', NULL, NULL, 0),
    ('Madecassoside', '{"Centella Asiatica Extract",Asiaticoside}'::text[], 'soothing', 5, 7, 0),
    ('Malic Acid', '{"Apple Acid","Hydroxybutanedioic Acid"}'::text[], 'aha', 3.5, 4.5, 0),
    ('Mandelic Acid', '{"Phenylglycolic Acid","Amygdalic Acid"}'::text[], 'aha', 3.5, 4.5, 0),
    ('Marula Oil', '{"Sclerocarya Birrea Seed Oil"}'::text[], 'botanical', NULL, NULL, 3),
    ('Matrixyl 3000', '{"Palmitoyl Tripeptide-1","Palmitoyl Tetrapeptide-7"}'::text[], 'peptide', 5, 7, 0),
    ('Meradimate', '{"Menthyl Anthranilate"}'::text[], 'sunscreen', NULL, NULL, 0),
    ('Methylchloroisothiazolinone', '{MCI,"Kathon CG"}'::text[], 'preservative', NULL, NULL, 0),
    ('Methylisothiazolinone', '{MIT,MI,"Neolone 950"}'::text[], 'preservative', NULL, NULL, 0),
    ('Methylparaben', '{"Methyl 4-hydroxybenzoate",Paraben}'::text[], 'preservative', NULL, NULL, 0),
    ('Mexoryl SX', '{Ecamsule,"Terephthalylidene Dicamphor Sulfonic Acid"}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Mexoryl XL', '{"Drometrizole Trisiloxane"}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Mineral Oil', '{"Paraffinum Liquidum",Petrolatum}'::text[], 'oil', NULL, NULL, 0),
    ('Mugwort Extract', '{"Artemisia Vulgaris Extract",Ssuk}'::text[], 'soothing', 5, 7, 0),
    ('Mushroom Extract', '{"Tremella Fuciformis","Snow Mushroom","Ganoderma Extract"}'::text[], 'botanical', NULL, NULL, 0),
    ('Neem Oil', '{"Azadirachta Indica Seed Oil"}'::text[], 'botanical', NULL, NULL, 2),
    ('Neo Heliopan AP', '{"Bisdisulizole Disodium","Disodium Phenyl Dibenzimidazole Tetrasulfonate"}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Niacinamide', '{"Vitamin B3",Nicotinamide,"Niacin Amide"}'::text[], 'vitamin', 5, 7, 0),
    ('Oat Extract', '{"Avena Sativa Kernel Extract","Colloidal Oatmeal"}'::text[], 'botanical', NULL, NULL, 0),
    ('Octinoxate', '{"Octyl Methoxycinnamate",OMC,"Ethylhexyl Methoxycinnamate"}'::text[], 'sunscreen', NULL, NULL, 0),
    ('Octisalate', '{"Octyl Salicylate","Ethylhexyl Salicylate"}'::text[], 'sunscreen', NULL, NULL, 0),
    ('Octocrylene', '{"2 - Ethylhexyl 2 - Cyano -3,
        3 - diphenylprop -2 - enoate"}'::text[], 'sunscreen', NULL, NULL, 0),
    ('Olive Oil', '{"Olea Europaea Fruit Oil"}'::text[], 'oil', NULL, NULL, 2),
    ('Oxybenzone', '{"Benzophenone -3","BP -3"}'::text[], 'sunscreen', NULL, NULL, 0),
    ('Padimate O', '{"OD - PABA","Octyl Dimethyl PABA"}'::text[], 'sunscreen', NULL, NULL, 0),
    ('Panthenol', '{"Provitamin B5",D-Panthenol,Dexpanthenol}'::text[], 'soothing', 5, 7, 0),
    ('Papain', '{"Papaya Enzyme","Carica Papaya Extract"}'::text[], 'enzyme', 6, 7, 0),
    ('Parfum', '{Fragrance,Perfume}'::text[], 'fragrance', NULL, NULL, 0),
    ('Phenol Peel', '{"Carbolic Acid","Deep Peel"}'::text[], 'skin_tone_risk', NULL, NULL, 0),
    ('Phenoxyethanol', '{"Ethylene Glycol Monophenyl Ether","Rose Ether"}'::text[], 'preservative', NULL, NULL, 0),
    ('Phytic Acid', '{"Inositol Hexaphosphate",IP6}'::text[], 'brightening', 3.5, 5, 0),
    ('Polyglutamic Acid', '{PGA,Gamma-PGA}'::text[], 'humectant', 5, 7, 0),
    ('Polysilicone -15', '{"Parsol SLX",Dimethicodiethylbenzalmalonate}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Potassium Sorbate', '{Sorbate,E202}'::text[], 'preservative', NULL, NULL, 0),
    ('Propylparaben', '{"Propyl 4-hydroxybenzoate",Paraben}'::text[], 'preservative', NULL, NULL, 0),
    ('Pyroglutamic Acid', '{PCA,5-Oxoproline}'::text[], 'humectant', 4, 6, 0),
    ('Resveratrol', '{Trans-Resveratrol,"Grape Skin Extract"}'::text[], 'botanical', NULL, NULL, 0),
    ('Retinal', '{Retinaldehyde,"Vitamin A Aldehyde"}'::text[], 'retinoid', 5.5, 7, 2),
    ('Retinol', '{"Vitamin A","Pure Retinol",ROL}'::text[], 'retinoid', 5.5, 7, 2),
    ('Retinyl Palmitate', '{"Vitamin A Palmitate","Retinol Palmitate"}'::text[], 'retinoid', 5.5, 7, 2),
    ('Rosehip Oil', '{"Rosa Canina Fruit Oil","Rosehip Seed Oil"}'::text[], 'botanical', NULL, NULL, 1),
    ('Rosehip Seed Oil', '{"Rosa Canina","Rosehip Oil"}'::text[], 'oil', NULL, NULL, 1),
    ('Salicylic Acid', '{BHA,"Beta Hydroxy Acid",SA,"2-Hydroxybenzoic Acid"}'::text[], 'bha', 3, 4, 0),
    ('Sandalwood Extract', '{"Santalum Album Extract","Sandalwood Oil"}'::text[], 'botanical', NULL, NULL, 0),
    ('Sea Buckthorn Oil', '{"Hippophae Rhamnoides Oil"}'::text[], 'oil', NULL, NULL, 0),
    ('Sea Kelp Bioferment', '{"Laminaria Saccharina","Kelp Extract"}'::text[], 'active', 5, 7, 0),
    ('Shea Butter', '{"Butyrospermum Parkii","Shea Butter Extract"}'::text[], 'emollient', NULL, NULL, 0),
    ('Sodium Ascorbyl Phosphate', '{SAP,"Vitamin C derivative"}'::text[], 'antioxidant', 6, 7, 0),
    ('Sodium Benzoate', '{Benzoate,E211}'::text[], 'preservative', NULL, NULL, 0),
    ('Sodium Hyaluronate', '{"HA Salt","Low Molecular Weight HA"}'::text[], 'humectant', 5, 7, 0),
    ('Squalane', '{"Hydrogenated Olive Oil","Shark Squalane","Plant Squalane"}'::text[], 'emollient', NULL, NULL, 1),
    ('Succinic Acid', '{"Butanedioic Acid"}'::text[], 'active', 3.5, 5, 0),
    ('Sweet Almond Oil', '{"Prunus Amygdalus Dulcis Oil"}'::text[], 'oil', NULL, NULL, 2),
    ('Tartaric Acid', '{"Grape Acid","Dihydroxysuccinic Acid"}'::text[], 'aha', 3, 4, 0),
    ('Tea Tree Oil', '{"Melaleuca Alternifolia Leaf Oil",TTO}'::text[], 'botanical', NULL, NULL, 1),
    ('Tinosorb M', '{"Methylene Bis - Benzotriazolyl Tetramethylbutylphenol",MBBT}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Tinosorb S', '{"Bis - Ethylhexyloxyphenol Methoxyphenyl Triazine",BEMT}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Titanium Dioxide', '{TiO2,"CI 77891","Physical SPF"}'::text[], 'sunscreen', NULL, NULL, 0),
    ('Tocopherol', '{"Vitamin E","Alpha Tocopherol","Mixed Tocopherols"}'::text[], 'antioxidant', NULL, NULL, 2),
    ('Tranexamic Acid', '{TXA,"Trans-4-aminomethylcyclohexane-1-carboxylic acid"}'::text[], 'brightening', 5, 7, 0),
    ('Tremella Mushroom', '{"Tremella Fuciformis Sporocarp Extract","Snow Mushroom"}'::text[], 'humectant', 5, 7, 0),
    ('Tretinoin', '{"Retinoic Acid","All-trans Retinoic Acid",Retin-A}'::text[], 'retinoid', 5.5, 7, 2),
    ('Trichloroacetic Acid', '{TCA,"TCA Peel"}'::text[], 'skin_tone_risk', 1, 2, 0),
    ('Turmeric Extract', '{"Curcuma Longa Root Extract",Curcumin}'::text[], 'botanical', NULL, NULL, 0),
    ('Urea', '{Carbamide,"Carbonyl Diamide"}'::text[], 'humectant', 4, 7, 0),
    ('Uvinul A Plus', '{"Diethylamino Hydroxybenzoyl Hexyl Benzoate",DHHB}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Uvinul T 150', '{"Ethylhexyl Triazone",EHT,"Octyl Triazone"}'::text[], 'sunscreen_intl', NULL, NULL, 0),
    ('Willow Bark Extract', '{"Salix Alba Bark Extract","Natural BHA"}'::text[], 'botanical', NULL, NULL, 0),
    ('Zinc Oxide', '{ZnO,"Zinc White","Physical SPF"}'::text[], 'sunscreen', NULL, NULL, 0),
    ('Zinc PCA', '{"Zinc L-Pyrrolidone Carboxylate","Zinc Salt"}'::text[], 'antibacterial', 5, 7, 0)
ON CONFLICT (inci_name) DO NOTHING;

COMMIT;


-- ======================================================================
-- aidatabase.sql
-- ======================================================================

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

-- ======================================================================
-- migrations/002_ingredient_catalog.sql
-- ======================================================================

-- SkincareSync migration 002: large-scale ingredient catalog + search infrastructure.
--
-- Base schema lives in aidatabase.sql (migration 001). This migration extends the
-- existing `ingredients` table in place so that every foreign key in
-- `interactions`, `parser_unknowns` and `interaction_gaps` keeps pointing at the
-- same `ingridient_id` values. No curated row is deleted or renumbered.
--
-- Data source: Open Beauty Facts cosmetic ingredient taxonomy (derived from the
-- European Commission CosIng database). Licensed under the Open Database License
-- (ODbL) v1.0. See ATTRIBUTION.md.
--
-- Idempotent: safe to re-run.

BEGIN;

-- Trigram matching powers typo tolerance and partial matching; unaccent lets
-- accented international names match their unaccented spelling.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- ---------------------------------------------------------------------------
-- INCI normalization, mirrored from skincaresync.parser.normalize_token so that
-- SQL-side lookups and the Python resolver agree on what "the same ingredient"
-- means. Must stay IMMUTABLE to be usable in a generated column and an index.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION inci_normalize(value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT lower(
        btrim(
            regexp_replace(
                regexp_replace(
                    regexp_replace(
                        regexp_replace(coalesce(value, ''), '\d+(\.\d+)?\s*%', '', 'g'),
                        '\([^)]*\)', '', 'g'
                    ),
                    '[\s.;:]+$', '', 'g'
                ),
                '\s+', ' ', 'g'
            )
        )
    );
$$;

-- ---------------------------------------------------------------------------
-- Catalog columns
-- ---------------------------------------------------------------------------

-- Real INCI names for multi-botanical ferment complexes run to ~1,900
-- characters, well past the original varchar(500). Widen rather than truncate,
-- so imported regulatory names stay intact. The generated normalized_name
-- column depends on inci_name, so it is dropped here and recreated below.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'ingredients'
          AND column_name = 'inci_name'
          AND data_type = 'character varying'
    ) THEN
        -- Both the generated column and the search trigger reference inci_name;
        -- each is recreated further down this migration.
        DROP TRIGGER IF EXISTS ingredients_search_document_trg ON ingredients;
        ALTER TABLE ingredients DROP COLUMN IF EXISTS normalized_name;
        ALTER TABLE ingredients
            ALTER COLUMN inci_name TYPE TEXT,
            ALTER COLUMN category TYPE TEXT;
    END IF;
END
$$;

ALTER TABLE ingredients
    ADD COLUMN IF NOT EXISTS alt_names TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS functions TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS cas_number TEXT,
    ADD COLUMN IF NOT EXISTS einecs_number TEXT,
    ADD COLUMN IF NOT EXISTS inn_name TEXT,
    ADD COLUMN IF NOT EXISTS ph_eur_name TEXT,
    ADD COLUMN IF NOT EXISTS cosing_ref TEXT,
    ADD COLUMN IF NOT EXISTS obf_id TEXT,
    ADD COLUMN IF NOT EXISTS wikidata_id TEXT,
    ADD COLUMN IF NOT EXISTS restriction TEXT,
    ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'curated',
    ADD COLUMN IF NOT EXISTS source_updated_on DATE,
    -- Denormalized count of interaction rules referencing this ingredient.
    -- Used to rank ingredients the compatibility engine actually knows about.
    ADD COLUMN IF NOT EXISTS interaction_count INTEGER NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'ingredients' AND column_name = 'normalized_name'
    ) THEN
        ALTER TABLE ingredients
            ADD COLUMN normalized_name TEXT
            GENERATED ALWAYS AS (inci_normalize(inci_name)) STORED;
    END IF;

END
$$;

-- One tsvector covering canonical name, every alternate/international name,
-- curated synonyms, chemical identifiers and the description.
--
-- Maintained by trigger rather than as a GENERATED column because
-- array_to_string() is only STABLE, so Postgres rejects it in a generation
-- expression. Marking a wrapper IMMUTABLE would be a lie about volatility.
ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS search_document tsvector;

-- Flattened alternate + curated names. Searching these via
-- `EXISTS (SELECT ... FROM unnest(alt_names))` cannot use an index and forces a
-- sequential scan on every query; a single text column can be trigram-indexed.
ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS alias_text TEXT;

CREATE OR REPLACE FUNCTION ingredients_search_document_refresh()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.alias_text := array_to_string(
        NEW.alt_names || NEW.synonyms
            || ARRAY[coalesce(NEW.inn_name, ''), coalesce(NEW.ph_eur_name, '')],
        ' | '
    );
    NEW.search_document := to_tsvector(
        'english'::regconfig,
        coalesce(NEW.inci_name, '') || ' ' ||
        coalesce(array_to_string(NEW.alt_names, ' '), '') || ' ' ||
        coalesce(array_to_string(NEW.synonyms, ' '), '') || ' ' ||
        coalesce(NEW.inn_name, '') || ' ' ||
        coalesce(NEW.ph_eur_name, '') || ' ' ||
        coalesce(NEW.cas_number, '') || ' ' ||
        coalesce(NEW.einecs_number, '') || ' ' ||
        coalesce(NEW.category, '') || ' ' ||
        coalesce(array_to_string(NEW.functions, ' '), '') || ' ' ||
        coalesce(NEW.description, '')
    );
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS ingredients_search_document_trg ON ingredients;
CREATE TRIGGER ingredients_search_document_trg
    BEFORE INSERT OR UPDATE OF
        inci_name, alt_names, synonyms, inn_name, ph_eur_name,
        cas_number, einecs_number, category, functions, description
    ON ingredients
    FOR EACH ROW
    EXECUTE FUNCTION ingredients_search_document_refresh();

-- Backfill existing rows (no-op on re-run beyond recomputing the same value).
UPDATE ingredients SET inci_name = inci_name
WHERE search_document IS NULL OR alias_text IS NULL;

ALTER TABLE ingredients
    DROP CONSTRAINT IF EXISTS ingredients_source_check;
ALTER TABLE ingredients
    ADD CONSTRAINT ingredients_source_check
    CHECK (source IN ('curated', 'open-beauty-facts'));

-- ---------------------------------------------------------------------------
-- Search indexes
-- ---------------------------------------------------------------------------

-- Full-text search across the whole document.
CREATE INDEX IF NOT EXISTS ingredients_search_document_idx
    ON ingredients USING GIN (search_document);

-- Trigram indexes: partial matching ("cetyl alc") and typo tolerance ("niacinimide").
CREATE INDEX IF NOT EXISTS ingredients_inci_name_trgm_idx
    ON ingredients USING GIN (inci_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ingredients_normalized_name_trgm_idx
    ON ingredients USING GIN (normalized_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ingredients_alias_text_trgm_idx
    ON ingredients USING GIN (alias_text gin_trgm_ops);

-- Exact/prefix lookups used by the resolver and by exact-match ranking.
CREATE INDEX IF NOT EXISTS ingredients_normalized_name_idx
    ON ingredients (normalized_name);

-- Array containment for alternate-name and category filtering.
CREATE INDEX IF NOT EXISTS ingredients_alt_names_idx
    ON ingredients USING GIN (alt_names);
CREATE INDEX IF NOT EXISTS ingredients_functions_idx
    ON ingredients USING GIN (functions);

-- Alphabetical browsing.
CREATE INDEX IF NOT EXISTS ingredients_initial_idx
    ON ingredients (upper(left(inci_name, 1)));

-- Import identity: one row per upstream taxonomy entry, enabling idempotent upserts.
CREATE UNIQUE INDEX IF NOT EXISTS ingredients_obf_id_key
    ON ingredients (obf_id) WHERE obf_id IS NOT NULL;

-- Note: normalized_name is deliberately NOT unique. The curated catalog contains
-- intentional near-duplicates such as 'Hydroquinone' and 'Hydroquinone 4%', which
-- both normalize to 'hydroquinone' and are both referenced by interaction rules.
-- Import-time deduplication is handled in scripts/import_ingredient_catalog.py.

CREATE INDEX IF NOT EXISTS ingredients_source_idx ON ingredients (source);
CREATE INDEX IF NOT EXISTS ingredients_interaction_count_idx
    ON ingredients (interaction_count DESC);

-- ---------------------------------------------------------------------------
-- Provenance of each bulk import run.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ingredient_import_runs (
    import_run_id SERIAL PRIMARY KEY,
    source TEXT NOT NULL,
    source_url TEXT,
    source_license TEXT,
    source_last_modified TEXT,
    entries_read INTEGER NOT NULL DEFAULT 0,
    inserted INTEGER NOT NULL DEFAULT 0,
    enriched INTEGER NOT NULL DEFAULT 0,
    skipped_duplicates INTEGER NOT NULL DEFAULT 0,
    finished_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

COMMIT;


-- ======================================================================
-- migrations/003_ingredient_search_alias.sql
-- ======================================================================

-- Follow-up to 002: alias_text was added to the migration file after an earlier
-- run, so some databases have the catalog without the flattened alias column
-- the trigram index needs. Idempotent.

BEGIN;

ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS alias_text TEXT;

-- Recreate the trigger in case this database was migrated from an older 002.
CREATE OR REPLACE FUNCTION ingredients_search_document_refresh()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.alias_text := array_to_string(
        NEW.alt_names || NEW.synonyms
            || ARRAY[coalesce(NEW.inn_name, ''), coalesce(NEW.ph_eur_name, '')],
        ' | '
    );
    NEW.search_document := to_tsvector(
        'english'::regconfig,
        coalesce(NEW.inci_name, '') || ' ' ||
        coalesce(array_to_string(NEW.alt_names, ' '), '') || ' ' ||
        coalesce(array_to_string(NEW.synonyms, ' '), '') || ' ' ||
        coalesce(NEW.inn_name, '') || ' ' ||
        coalesce(NEW.ph_eur_name, '') || ' ' ||
        coalesce(NEW.cas_number, '') || ' ' ||
        coalesce(NEW.einecs_number, '') || ' ' ||
        coalesce(NEW.category, '') || ' ' ||
        coalesce(array_to_string(NEW.functions, ' '), '') || ' ' ||
        coalesce(NEW.description, '')
    );
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS ingredients_search_document_trg ON ingredients;
CREATE TRIGGER ingredients_search_document_trg
    BEFORE INSERT OR UPDATE OF
        inci_name, alt_names, synonyms, inn_name, ph_eur_name,
        cas_number, einecs_number, category, functions, description
    ON ingredients
    FOR EACH ROW
    EXECUTE FUNCTION ingredients_search_document_refresh();

UPDATE ingredients SET inci_name = inci_name
WHERE alias_text IS NULL;

CREATE INDEX IF NOT EXISTS ingredients_alias_text_trgm_idx
    ON ingredients USING GIN (alias_text gin_trgm_ops);

CREATE INDEX IF NOT EXISTS ingredients_restriction_idx
    ON ingredients (ingridient_id)
    WHERE restriction IS NOT NULL AND restriction <> '';

COMMIT;


-- ======================================================================
-- migrations/004_product_catalog.sql
-- ======================================================================

-- Local product catalog: persist ingredient lists so lookups do not depend on
-- Open Beauty Facts having a complete record.
--
-- Sources:
--   dailymed           FDA Structured Product Labels (OTC/drug products)
--   open_beauty_facts  cached community records that did include an INCI list
--   manual             curated rows
--
-- Idempotent.

BEGIN;

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS ndc TEXT,
    ADD COLUMN IF NOT EXISTS setid TEXT,
    ADD COLUMN IF NOT EXISTS product_url TEXT,
    ADD COLUMN IF NOT EXISTS image_url TEXT,
    ADD COLUMN IF NOT EXISTS search_aliases TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW();

ALTER TABLE products DROP CONSTRAINT IF EXISTS products_source_check;
ALTER TABLE products
    ADD CONSTRAINT products_source_check
    CHECK (source IN (
        'manual',
        'open_beauty_facts',
        'user_submitted',
        'dailymed'
    ));

-- One stored row per DailyMed label; barcodes remain unique when present.
CREATE UNIQUE INDEX IF NOT EXISTS products_setid_key
    ON products (setid)
    WHERE setid IS NOT NULL;

CREATE INDEX IF NOT EXISTS products_ndc_idx
    ON products (ndc)
    WHERE ndc IS NOT NULL;

CREATE INDEX IF NOT EXISTS products_brand_name_idx
    ON products (LOWER(brand), LOWER(name));

CREATE INDEX IF NOT EXISTS products_aliases_idx
    ON products USING GIN (search_aliases);

COMMIT;


-- ======================================================================
-- migrations/005_product_variants_and_search_indexes.sql
-- ======================================================================

-- Follow-up to 004.
--
-- 1. One SPL document can describe several distinct marketed products (different
--    strengths or pack forms, each with its own ingredient list). The unique
--    index on `setid` alone forced all of them onto a single row, so every
--    variant after the first silently overwrote the previous one and users could
--    be shown the ingredient list of a product they did not search for.
--    The replacement key keeps one row per (label, variant), identified by NDC
--    where the label provides one and by product name otherwise.
--
-- 2. Product lookup stripped every non-ASCII character from the query before
--    matching, so "Bioré" became the token "bior" and never matched a stored
--    "Biore", while "L'Oréal" became "or" + "al" and matched almost everything.
--    A folded search column fixes both ends of the comparison and, unlike the
--    three OR'd LIKE conditions it replaces, can be trigram-indexed.
--
--    `unaccent()` is STABLE, not IMMUTABLE, so it cannot appear in a generated
--    column or an index expression. The column is maintained by a trigger for
--    the same reason `search_document` on `ingredients` is.
--
-- 3. The catalog browse view (no query, no filters) sorts 22k rows by
--    curated-first, then interaction count. Without a matching index that is a
--    full scan plus sort on every page load.
--
-- Idempotent. The new product key is strictly more permissive than the one it
-- replaces, so no existing row can violate it.

BEGIN;

CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 1. Product variant identity ------------------------------------------------
DROP INDEX IF EXISTS products_setid_key;

CREATE UNIQUE INDEX IF NOT EXISTS products_setid_variant_key
    ON products (setid, COALESCE(NULLIF(ndc, ''), lower(name)))
    WHERE setid IS NOT NULL;

-- 2. Accent-folded product search -------------------------------------------
ALTER TABLE products ADD COLUMN IF NOT EXISTS search_text TEXT;

CREATE OR REPLACE FUNCTION products_search_text_refresh()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.search_text := unaccent(lower(
        coalesce(NEW.brand, '') || ' ' ||
        coalesce(NEW.name, '') || ' ' ||
        coalesce(array_to_string(NEW.search_aliases, ' '), '')
    ));
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS products_search_text_trg ON products;
CREATE TRIGGER products_search_text_trg
    BEFORE INSERT OR UPDATE OF brand, name, search_aliases
    ON products
    FOR EACH ROW
    EXECUTE FUNCTION products_search_text_refresh();

-- Backfill existing rows (no-op on re-run beyond recomputing the same value).
UPDATE products SET name = name WHERE search_text IS NULL;

CREATE INDEX IF NOT EXISTS products_search_text_trgm_idx
    ON products USING GIN (search_text gin_trgm_ops);

-- Only rows with an ingredient list are ever returned by search_local.
CREATE INDEX IF NOT EXISTS products_has_ingredients_idx
    ON products (product_id)
    WHERE raw_ingredient_list <> '';

-- 3. Catalog browse ordering -------------------------------------------------
CREATE INDEX IF NOT EXISTS ingredients_browse_idx
    ON ingredients (((source = 'curated')) DESC, interaction_count DESC, inci_name);

COMMIT;


-- ======================================================================
-- migrations/006_drop_unused_schema.sql
-- ======================================================================

-- Drop schema that no code has ever referenced.
--
-- `skin_profiles`, `routines` and `routine_products` were created in the base
-- schema for saved, persisted routines. That feature was never built: the API
-- takes a routine in the request body and returns an analysis, holding nothing
-- between requests. All three tables are empty and no module imports them.
--
-- `products.parsed_ingredient_ids` was meant to cache the resolved ingredient
-- ids for a stored product. Nothing ever wrote it; it is `'{}'` on every row.
-- Resolution happens in memory against the shared resolver instead.
--
-- Verified empty before writing this migration:
--   skin_profiles 0, routines 0, routine_products 0 rows,
--   parsed_ingredient_ids populated on 0 of 3,286 products.
--
-- Deliberately kept:
--   products.verified   - editorial trust flag. Unused today, but ATTRIBUTION.md
--                         treats provenance as a first-class concern, so the hook
--                         is worth more than the byte it costs.
--   *.created_at        - row provenance. Not read by application code, which is
--                         normal for audit columns.
--
-- This migration is destructive and not idempotent-safe to reverse. The exact
-- CREATE TABLE statements are recoverable from git history:
--   git show c2279f9:aidatabase.sql
--
-- Restoring the saved-routines feature means re-adding these tables, which is a
-- schema design decision to make then rather than a rollback of this migration.

BEGIN;

-- Foreign keys run routine_products -> routines -> skin_profiles, so drop in
-- that order. routine_products also referenced products.
DROP TABLE IF EXISTS routine_products;
DROP TABLE IF EXISTS routines;
DROP TABLE IF EXISTS skin_profiles;

ALTER TABLE products DROP COLUMN IF EXISTS parsed_ingredient_ids;

COMMIT;


-- ======================================================================
-- migrations/007_auth.sql
-- ======================================================================

-- Authentication and authorization schema.
--
-- Four tables:
--   users              accounts, with a normalized email and an Argon2id hash
--   user_sessions      server-side, revocable sessions (one row per sign-in)
--   auth_tokens        single-use email verification and password reset tokens
--   auth_events        security audit log
--
-- Nothing here stores a plaintext secret. Passwords are Argon2id hashes;
-- session and email tokens are stored as SHA-256 digests of a 256-bit random
-- value, so a database disclosure cannot be replayed against the application.
-- SHA-256 rather than a KDF is correct here precisely because these are
-- high-entropy random tokens, not user-chosen passwords.
--
-- Email addresses are lowercased and trimmed by the API before they are stored,
-- and `email_normalized` recomputes that in the database so uniqueness is
-- enforced on the normalized form no matter how a row is inserted. The two
-- columns therefore agree today; the generated column exists so a direct SQL
-- insert cannot slip a duplicate past the unique index by varying case.
--
-- Reversible: see 007_auth.down.sql. Idempotent: safe to re-run.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    user_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email              TEXT NOT NULL,
    email_normalized   TEXT GENERATED ALWAYS AS (lower(btrim(email))) STORED,
    password_hash      TEXT NOT NULL,
    display_name       TEXT,
    role               TEXT NOT NULL DEFAULT 'user'
                       CHECK (role IN ('user', 'admin')),
    status             TEXT NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active', 'deactivated', 'deleted')),
    email_verified_at  TIMESTAMPTZ,

    -- Bumped on password change, reset, and "sign out everywhere". Any session
    -- or token issued before this instant is refused, which revokes them
    -- without needing to enumerate and delete rows first.
    credentials_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Throttles password attempts per account, independent of source address.
    failed_login_count INTEGER NOT NULL DEFAULT 0,
    locked_until       TIMESTAMPTZ,

    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at         TIMESTAMPTZ,

    CONSTRAINT users_email_not_blank CHECK (btrim(email) <> ''),
    -- A deleted account keeps its row so audit history and foreign keys stay
    -- intact, but must carry a timestamp saying so.
    CONSTRAINT users_deleted_consistent
        CHECK ((status = 'deleted') = (deleted_at IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS users_email_normalized_key
    ON users (email_normalized);

CREATE INDEX IF NOT EXISTS users_role_idx ON users (role) WHERE role <> 'user';
CREATE INDEX IF NOT EXISTS users_status_idx ON users (status) WHERE status <> 'active';

-- ---------------------------------------------------------------------------
-- user_sessions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_sessions (
    session_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,

    -- SHA-256 of the opaque token held in the cookie. The token itself is
    -- never stored, so this column cannot be replayed.
    token_hash       BYTEA NOT NULL,

    -- Coarse client description for the "your sessions" screen. Truncated and
    -- never used for authorization.
    user_agent       TEXT,
    ip_address       INET,

    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Absolute expiry. Idle expiry is derived from last_seen_at in the query.
    expires_at       TIMESTAMPTZ NOT NULL,
    revoked_at       TIMESTAMPTZ,
    revoked_reason   TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS user_sessions_token_hash_key
    ON user_sessions (token_hash);

-- Serves both session lookup by user and the "sign out all devices" sweep.
CREATE INDEX IF NOT EXISTS user_sessions_active_idx
    ON user_sessions (user_id, expires_at)
    WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS user_sessions_expires_idx ON user_sessions (expires_at);

-- ---------------------------------------------------------------------------
-- auth_tokens
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth_tokens (
    auth_token_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    purpose       TEXT NOT NULL CHECK (purpose IN ('email_verification', 'password_reset')),

    token_hash    BYTEA NOT NULL,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ NOT NULL,
    -- Set the moment a token is redeemed, which is what makes it single-use.
    consumed_at   TIMESTAMPTZ,

    CONSTRAINT auth_tokens_expires_after_creation CHECK (expires_at > created_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS auth_tokens_token_hash_key
    ON auth_tokens (token_hash);

-- Issuing a new token invalidates outstanding ones for the same purpose; this
-- index serves that sweep and the redemption lookup.
CREATE INDEX IF NOT EXISTS auth_tokens_pending_idx
    ON auth_tokens (user_id, purpose)
    WHERE consumed_at IS NULL;

CREATE INDEX IF NOT EXISTS auth_tokens_expires_idx ON auth_tokens (expires_at);

-- ---------------------------------------------------------------------------
-- auth_events
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth_events (
    auth_event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Nullable and ON DELETE SET NULL: a failed sign-in for an address that was
    -- never registered has no user, and purging a user must not erase the
    -- security history of the account.
    user_id       BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
    event_type    TEXT NOT NULL,
    -- Free-form, but the application never writes a token, hash or password here.
    detail        JSONB NOT NULL DEFAULT '{}'::jsonb,
    ip_address    INET,
    user_agent    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS auth_events_user_idx ON auth_events (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS auth_events_type_idx ON auth_events (event_type, created_at DESC);

-- ---------------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION users_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS users_touch_updated_at_trg ON users;
CREATE TRIGGER users_touch_updated_at_trg
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION users_touch_updated_at();

-- No seed administrator is created here. Promoting the first real account is a
-- deliberate operator action; see scripts/grant_admin.py.

COMMIT;


-- ======================================================================
-- migrations/008_social_identities.sql
-- ======================================================================

-- Social sign-in (Google, Apple).
--
-- Two tables and one column change:
--
--   user_identities   one row per (provider, provider account) linked to a user
--   oauth_flows       short-lived server-side state for an in-progress sign-in
--   users.password_hash becomes nullable
--
-- The nullable password is the substantive change. An account created through
-- Google has no password and never will unless the user sets one, so a NOT NULL
-- column would force a placeholder -- and a placeholder in a password column is
-- exactly the kind of value that eventually gets compared against. NULL states
-- plainly that password sign-in is unavailable for this account.
--
-- `oauth_flows` exists so the OAuth state, PKCE verifier and nonce live on the
-- server rather than in a signed cookie. Signing a cookie would mean choosing
-- and implementing a construction; a random opaque key in an HttpOnly cookie
-- pointing at a row needs no cryptography of our own, and gets single-use and
-- expiry for free -- the same shape as auth_tokens.
--
-- Reversible: see 008_social_identities.down.sql. Idempotent.

BEGIN;

-- ---------------------------------------------------------------------------
-- users.password_hash becomes optional
-- ---------------------------------------------------------------------------
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;

-- An account must remain reachable by *some* means. This cannot be expressed as
-- a row constraint because the alternative lives in another table, so it is
-- enforced in the service layer (unlinking the last identity is refused when no
-- password is set). Recorded here so the intent is visible next to the schema.
COMMENT ON COLUMN users.password_hash IS
    'Argon2id hash, or NULL when the account signs in only through a linked '
    'provider. Never a placeholder value.';

-- ---------------------------------------------------------------------------
-- user_identities
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_identities (
    identity_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id        BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    provider       TEXT NOT NULL CHECK (provider IN ('google', 'apple')),

    -- The provider's stable identifier for the account ("sub"). This, not the
    -- email address, is the identity: an email can be reassigned by its domain
    -- owner, and matching on it alone would let a new owner inherit an account.
    subject        TEXT NOT NULL,

    -- What the provider asserted at link time. Informational only; the
    -- authoritative address stays on `users`.
    email          TEXT,
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,

    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at  TIMESTAMPTZ,

    CONSTRAINT user_identities_subject_not_blank CHECK (btrim(subject) <> '')
);

-- One provider account maps to exactly one user. Without this, two local
-- accounts could both claim the same Google account.
CREATE UNIQUE INDEX IF NOT EXISTS user_identities_provider_subject_key
    ON user_identities (provider, subject);

-- A user links a given provider at most once.
CREATE UNIQUE INDEX IF NOT EXISTS user_identities_user_provider_key
    ON user_identities (user_id, provider);

CREATE INDEX IF NOT EXISTS user_identities_user_idx ON user_identities (user_id);

-- ---------------------------------------------------------------------------
-- oauth_flows
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS oauth_flows (
    oauth_flow_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- SHA-256 of the opaque key held in a short-lived HttpOnly cookie. As with
    -- sessions, the key itself is never stored.
    flow_key_hash BYTEA NOT NULL,

    provider      TEXT NOT NULL CHECK (provider IN ('google', 'apple')),

    -- Compared against the `state` the provider echoes back, which is what ties
    -- the response to the browser that started the flow.
    state         TEXT NOT NULL,
    -- PKCE. Short-lived and single-use; the provider never sees it until the
    -- token exchange.
    code_verifier TEXT NOT NULL,
    -- Bound into the ID token so a captured token cannot be replayed.
    nonce         TEXT NOT NULL,

    -- Already reduced to a site-relative path before it is stored.
    redirect_to   TEXT NOT NULL DEFAULT '/',
    -- Set when an already-signed-in user is linking a provider rather than
    -- signing in, so the callback links instead of creating an account.
    link_user_id  BIGINT REFERENCES users(user_id) ON DELETE CASCADE,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ NOT NULL,
    consumed_at   TIMESTAMPTZ,

    CONSTRAINT oauth_flows_expires_after_creation CHECK (expires_at > created_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS oauth_flows_key_hash_key
    ON oauth_flows (flow_key_hash);

CREATE INDEX IF NOT EXISTS oauth_flows_expires_idx ON oauth_flows (expires_at);

COMMIT;


-- ======================================================================
-- migrations/009_catalog_interactions.sql
-- ======================================================================

-- Add evidence-backed interaction rules surfaced by production gap counts.
--
-- These studies evaluate formulated combinations. The rule copy deliberately
-- does not generalize that evidence into a claim that arbitrary products or
-- concentrations can always be layered safely.
--
-- Idempotent.

BEGIN;

WITH rule_seed (
    ingredient_a,
    ingredient_b,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    confidence,
    skin_type_modifier
) AS (
    VALUES
    (
        'Ascorbic Acid',
        'Tocopherol',
        'synergy',
        'medium',
        'direct',
        'Topical vitamins C and E provide complementary antioxidant activity; ferulic acid can improve their stability and photoprotective effect.',
        'A formulated vitamin C, vitamin E, and ferulic acid system showed greater photoprotection than the vitamin antioxidants alone. This evidence is formulation-specific.',
        'PMID:16185284',
        'verified',
        '{}'::jsonb
    ),
    (
        'Retinol',
        'Tocopherol',
        'synergy',
        'low',
        'direct',
        'Co-delivery of retinol and alpha-tocopherol may provide additive antioxidant and anti-inflammatory activity.',
        'A topical microemulsion study found an additive anti-inflammatory effect, but formulation and preclinical evidence do not establish the same effect for every pair of consumer products.',
        'PMID:32204073',
        'provisional',
        '{}'::jsonb
    ),
    (
        'Niacinamide',
        'Salicylic Acid',
        'synergy',
        'medium',
        'direct',
        'Niacinamide can support barrier tolerance while salicylic acid targets follicular congestion in a formulated acne treatment.',
        'A randomized trial found a multi-ingredient cream containing niacinamide and salicylic acid beneficial and well tolerated for mild-to-moderate acne. Results apply to the tested formulation.',
        'PMID:37941097',
        'provisional',
        '{}'::jsonb
    ),
    (
        'Glycolic Acid',
        'Salicylic Acid',
        'synergy',
        'low',
        'direct',
        'A carefully buffered alpha- and beta-hydroxy acid formulation can combine surface exfoliation with follicular activity.',
        'A randomized split-face trial supports a formulated glycolic-plus-salicylic peel. It does not establish that separately formulated strong acids should be layered without irritation monitoring.',
        'PMID:29164826',
        'provisional',
        '{"sensitive": "medium", "dry": "medium"}'::jsonb
    )
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
    rule_seed.confidence,
    rule_seed.skin_type_modifier
FROM rule_seed
JOIN ingredients ingredient_a ON LOWER(ingredient_a.inci_name) = LOWER(rule_seed.ingredient_a)
JOIN ingredients ingredient_b ON LOWER(ingredient_b.inci_name) = LOWER(rule_seed.ingredient_b)
ON CONFLICT DO NOTHING;

UPDATE ingredients ingredient
SET interaction_count = counts.total
FROM (
    SELECT ingredient_id, COUNT(*)::integer AS total
    FROM (
        SELECT ingredient_a_id AS ingredient_id FROM interactions
        UNION ALL
        SELECT ingredient_b_id AS ingredient_id FROM interactions
    ) referenced
    GROUP BY ingredient_id
) counts
WHERE ingredient.ingridient_id = counts.ingredient_id;

UPDATE interaction_gaps gap
SET status = 'published',
    last_seen = NOW()
FROM interactions interaction
WHERE LEAST(gap.ingredient_a_id, gap.ingredient_b_id) =
      LEAST(interaction.ingredient_a_id, interaction.ingredient_b_id)
  AND GREATEST(gap.ingredient_a_id, gap.ingredient_b_id) =
      GREATEST(interaction.ingredient_a_id, interaction.ingredient_b_id);

COMMIT;


-- ======================================================================
-- migrations/010_tretinoin_interactions.sql
-- ======================================================================

-- Tretinoin interaction rules, and a correction to the benzoyl peroxide rule.
--
-- Tretinoin reaches this engine differently from the rest of the catalog: it is
-- prescription-only, so it is typed by hand rather than copied off an INCI list
-- (see SPECIAL_CASE_ALIASES in skincaresync/parser.py). It is also the most
-- potent active most routines will ever contain, which makes its rules the ones
-- worth getting exactly right.
--
-- The benzoyl peroxide rule already existed but attributed the problem to
-- irritation. The measured mechanism is photo-oxidative degradation, and the
-- distinction changes the advice a user acts on: the risk of co-applying them
-- is not an irritated face, it is a prescription that quietly stops working.
-- Martin et al. mixed commercial tretinoin 0.025% gel with commercial benzoyl
-- peroxide 10% lotion and measured >50% tretinoin degradation within about two
-- hours of light exposure and 95% at 24 hours.
--
-- The same paper found adapalene stable under identical conditions, which is
-- why this correction is scoped to tretinoin rather than generalized to
-- retinoids. `conflict_scope` stays 'direct': the degradation needs the two in
-- contact, so an AM/PM split remains a complete answer and must not be flagged.
--
-- Deliberately NOT added, for want of a source that actually tests tretinoin:
-- tretinoin + ascorbic acid (no stability study found) and tretinoin +
-- niacinamide (the tolerability trials use adapalene, not tretinoin).
--
-- Idempotent.

BEGIN;

-- Correction, not a new rule: the pair is already in the table.
UPDATE interactions
SET mechanism = 'Benzoyl peroxide oxidises tretinoin on contact, and light drives the reaction. Adapalene is stable under the same conditions; this is specific to tretinoin.',
    description = 'Applied together, most of the tretinoin is destroyed before it can act — over half within about two hours of light exposure, and 95% by 24 hours. Using one in the morning and the other at night avoids this completely.',
    source_citation = 'PMID:9990414',
    confidence = 'verified',
    -- Degradation is chemistry, not irritation: it does not vary by skin type,
    -- so the rule must not escalate as though it did.
    skin_type_modifier = '{}'::jsonb,
    updated_at = NOW()
WHERE LEAST(ingredient_a_id, ingredient_b_id) =
      LEAST((SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'tretinoin'),
            (SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'benzoyl peroxide'))
  AND GREATEST(ingredient_a_id, ingredient_b_id) =
      GREATEST((SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'tretinoin'),
               (SELECT ingridient_id FROM ingredients WHERE LOWER(inci_name) = 'benzoyl peroxide'));

WITH rule_seed (
    ingredient_a,
    ingredient_b,
    interaction_type,
    severity,
    conflict_scope,
    mechanism,
    description,
    source_citation,
    confidence,
    skin_type_modifier
) AS (
    VALUES
    -- Retinoid stacking. Both rules describe cumulative retinoid load rather
    -- than a reaction between the two molecules, so the scope is 'both': the
    -- exposure adds up whether they are layered or split across AM and PM.
    (
        'Tretinoin',
        'Retinol',
        'caution',
        'high',
        'both',
        'Retinol is converted in the skin to retinoic acid, which is what tretinoin already supplies. Using both raises total retinoid exposure without adding a distinct mechanism.',
        'These are the same pathway at different strengths, so pairing them mostly adds irritation rather than benefit. Retinoid dermatitis is the main reason people abandon treatment.',
        'PMID:29611225',
        'provisional',
        '{"dry": "high", "sensitive": "high", "normal": "medium", "oily": "medium", "combination": "medium"}'::jsonb
    ),
    (
        'Tretinoin',
        'Adapalene',
        'caution',
        'high',
        'both',
        'Two topical retinoids acting on the same nuclear receptors. The effect on tolerability is additive; the therapeutic benefit is not.',
        'Running two prescription retinoids together increases irritation without a matching gain. Standard practice is one retinoid at a time, at a tolerated strength.',
        'PMID:29611225',
        'provisional',
        '{"dry": "high", "sensitive": "high", "normal": "medium", "oily": "medium", "combination": "medium"}'::jsonb
    )
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
    rule_seed.confidence,
    rule_seed.skin_type_modifier
FROM rule_seed
JOIN ingredients ingredient_a ON LOWER(ingredient_a.inci_name) = LOWER(rule_seed.ingredient_a)
JOIN ingredients ingredient_b ON LOWER(ingredient_b.inci_name) = LOWER(rule_seed.ingredient_b)
ON CONFLICT DO NOTHING;

UPDATE ingredients ingredient
SET interaction_count = counts.total
FROM (
    SELECT ingredient_id, COUNT(*)::integer AS total
    FROM (
        SELECT ingredient_a_id AS ingredient_id FROM interactions
        UNION ALL
        SELECT ingredient_b_id AS ingredient_id FROM interactions
    ) referenced
    GROUP BY ingredient_id
) counts
WHERE ingredient.ingridient_id = counts.ingredient_id;

UPDATE interaction_gaps gap
SET status = 'published',
    last_seen = NOW()
FROM interactions interaction
WHERE LEAST(gap.ingredient_a_id, gap.ingredient_b_id) =
      LEAST(interaction.ingredient_a_id, interaction.ingredient_b_id)
  AND GREATEST(gap.ingredient_a_id, gap.ingredient_b_id) =
      GREATEST(interaction.ingredient_a_id, interaction.ingredient_b_id);

COMMIT;
