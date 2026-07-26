-- QUESTION: "How are these two shows related?"
--
-- Parameters: :from_slug, :to_slug
-- Returns the shortest path, up to 3 hops, narrated so a person can read it:
--
--   Bear Grease --(both dig into Food and How We Eat)--> The Kitchen Sisters Present
--               --(both cover History, Retold)--> Slow Burn
--
-- Naming the nodes it passes through is the whole point. An earlier version chained only
-- the edge reasons, which produced "both dig into Food and How We Eat > both cover
-- History, Retold" -- true, but it never said what the two shows had in between, so it
-- explained nothing.
--
-- Written as three explicit joins rather than a recursive walk. A recursive CTE explores
-- every path from the source before checking whether any reached the target: with ~20
-- edges per node that is 20^3 partial paths, each doing string concatenation and a
-- visited-set scan, and it measured 594 ms. Both endpoints are known, so this meets in
-- the middle instead -- indexed from each end. Same answers, under 10 ms.
--
-- Bounded at 3 hops deliberately. Beyond three, every show connects to every other and
-- the explanation stops explaining.

WITH ends AS (
  SELECT
    (SELECT id FROM shows WHERE slug = :from_slug) AS src,
    (SELECT id FROM shows WHERE slug = :to_slug)   AS dst
),

-- A node's display name, whatever type it is. This is the price of a generic edges
-- table, and it buys paths through node types no hand-written join anticipated.
labelled AS (
  SELECT 'show' AS t, id, title AS label FROM shows
  UNION ALL SELECT 'theme',   id, name FROM themes
  UNION ALL SELECT 'arc',     id, name FROM arcs
),

h1 AS (
  SELECT 1 AS hops,
         '(' || e.why || ')' AS explanation,
         e.weight AS strength
  FROM ends, edges e
  WHERE e.src_type = 'show' AND e.src_id = ends.src
    AND e.dst_type = 'show' AND e.dst_id = ends.dst
),

h2 AS (
  SELECT 2 AS hops,
         '(' || a.why || ') -> ' || m.label || ' -> (' || b.why || ')' AS explanation,
         a.weight + b.weight AS strength
  FROM ends
  JOIN edges a ON a.src_type = 'show' AND a.src_id = ends.src
  JOIN labelled m ON m.t = a.dst_type AND m.id = a.dst_id
  JOIN edges b ON b.src_type = a.dst_type AND b.src_id = a.dst_id
              AND b.dst_type = 'show'     AND b.dst_id = ends.dst
  WHERE NOT (a.dst_type = 'show' AND a.dst_id = ends.src)
),

-- The characteristic 3-hop shape is show -> fine theme -> its parent theme -> show,
-- which is exactly the connection the two-tier vocabulary exists to express.
h3 AS (
  SELECT 3 AS hops,
         '(' || a.why || ') -> ' || m1.label || ' -> (' || b.why || ') -> ' || m2.label
              || ' -> (' || c.why || ')' AS explanation,
         a.weight + b.weight + c.weight AS strength
  FROM ends
  JOIN edges a ON a.src_type = 'show' AND a.src_id = ends.src
  JOIN labelled m1 ON m1.t = a.dst_type AND m1.id = a.dst_id
  JOIN edges b ON b.src_type = a.dst_type AND b.src_id = a.dst_id
  JOIN labelled m2 ON m2.t = b.dst_type AND m2.id = b.dst_id
  JOIN edges c ON c.src_type = b.dst_type AND c.src_id = b.dst_id
              AND c.dst_type = 'show'     AND c.dst_id = ends.dst
  WHERE NOT (a.dst_type = 'show' AND a.dst_id = ends.src)
    AND NOT (b.dst_type = 'show' AND b.dst_id = ends.src)
    AND NOT (b.dst_type = a.src_type AND b.dst_id = a.src_id)
)

SELECT hops, explanation, round(strength, 3) AS strength
FROM (SELECT * FROM h1 UNION ALL SELECT * FROM h2 UNION ALL SELECT * FROM h3)
ORDER BY hops ASC, strength DESC
LIMIT 1;
