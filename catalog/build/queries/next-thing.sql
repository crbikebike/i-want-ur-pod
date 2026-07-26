-- QUESTION: "I liked this show. What else scratches the same itch?"
--
-- Parameter: :slug -- the show the person just finished.
-- Returns up to 3 shows, each with the reason it was chosen.
--
-- Three rules make this different from a similarity sort:
--
-- 1. The fine-theme signal outranks the browse-theme signal. Two shows can share
--    "True Crime, Deep-Dive" and have nothing in common; sharing an episode-theme
--    profile means they actually dig at the same thing.
-- 2. Same publisher is PENALIZED, not rewarded. Recommending more of the same network's
--    back catalogue is what every other podcast app does, and the goal here is to move
--    someone toward work they would never have found.
-- 3. Anything sharing the seed's feed is excluded outright. Otherwise Revisionist
--    History's top recommendation is "The Staten Island Problem", which IS Revisionist
--    History under another catalogue entry.

WITH seed AS (
  SELECT id, feed_url, network_id FROM shows WHERE slug = :slug
),
scored AS (
  SELECT
    e.dst_id                       AS show_id,
    max(CASE WHEN e.kind = 'shares_fine_theme' THEN e.weight END) AS fine,
    max(CASE WHEN e.kind = 'shares_theme'      THEN e.weight END) AS coarse,
    -- Keep the reason attached to the strongest signal, so the sentence shown to the
    -- person is the one that actually drove the choice.
    max(CASE WHEN e.kind = 'shares_fine_theme' THEN e.weight END || '|' ||
        CASE WHEN e.kind = 'shares_fine_theme' THEN e.why ELSE '' END) AS fine_why,
    max(CASE WHEN e.kind = 'shares_theme' THEN e.why END) AS coarse_why
  FROM edges e, seed
  WHERE e.src_type = 'show' AND e.src_id = seed.id AND e.dst_type = 'show'
    AND e.kind IN ('shares_fine_theme', 'shares_theme')
  GROUP BY e.dst_id
)
SELECT
  s.slug,
  s.title,
  s.why,
  round(
    (coalesce(sc.fine, 0) * 2.0 + coalesce(sc.coarse, 0))
    * CASE WHEN s.network_id IS NOT NULL AND s.network_id = seed.network_id
           THEN 0.5 ELSE 1.0 END,
    4
  ) AS score,
  coalesce(nullif(substr(sc.fine_why, instr(sc.fine_why, '|') + 1), ''), sc.coarse_why) AS why_related,
  s.depth
FROM scored sc
JOIN shows s ON s.id = sc.show_id, seed
WHERE s.feed_url <> seed.feed_url          -- rule 3: not the same programme
  -- Only 'cut' is excluded, not 'suspect'. Suspect means "a human should look at this",
  -- not "this is bad" -- and filtering it here hid Revisionist History, a flagship show,
  -- purely because a duplicate catalogue entry points at its feed. Rule 3 already
  -- removes the actual duplicate.
  AND s.include_verdict <> 'cut'
  AND s.id <> seed.id
ORDER BY score DESC, s.title
LIMIT 3;
