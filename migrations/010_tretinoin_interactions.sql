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
