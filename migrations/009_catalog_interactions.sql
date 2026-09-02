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
