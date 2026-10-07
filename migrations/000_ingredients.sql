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
