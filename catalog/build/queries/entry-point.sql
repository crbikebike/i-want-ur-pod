-- QUESTION: "This show has 700 episodes. Where do I start?"
--
-- Parameter: :slug
-- Returns one recommendation: an arc where the show has one, otherwise a single episode.
--
-- The ranking lives in edges.entry_point, computed at build time (see edges.py) so this
-- query stays cheap enough to run while a screen is drawing. A verified arc beats any
-- single episode, because a verified arc is a story a person confirmed hangs together.
--
-- In Phase 2 a human can override the stored choice; that override lands in `edits` and
-- survives every rebuild, so this query does not change.

SELECT
  s.title                                  AS show_title,
  (SELECT count(*) FROM episodes WHERE show_id = s.id AND available = 1) AS show_episodes,
  e.dst_type                               AS start_with,
  e.why                                    AS recommendation,
  CASE e.dst_type
    WHEN 'arc'     THEN (SELECT name  FROM arcs     WHERE id = e.dst_id)
    WHEN 'episode' THEN (SELECT title FROM episodes WHERE id = e.dst_id)
  END                                      AS target,
  CASE e.dst_type
    WHEN 'arc' THEN (SELECT count(*) FROM episodes WHERE arc_id = e.dst_id)
    ELSE 1
  END                                      AS target_episodes,
  CASE e.dst_type
    WHEN 'arc' THEN (SELECT confidence FROM arcs WHERE id = e.dst_id)
    ELSE NULL
  END                                      AS arc_confidence
FROM shows s
JOIN edges e ON e.src_type = 'show' AND e.src_id = s.id AND e.kind = 'entry_point'
WHERE s.slug = :slug;
