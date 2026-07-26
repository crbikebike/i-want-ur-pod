-- The permanent catalog. Spec: docs/specs/phase-1-catalog-and-graph.md
--
-- Typed tables carry the facts. One generic `edges` table carries relationships, so
-- traversal and "explain the connection" are written once instead of per path.
--
-- Two things this file deliberately does NOT have:
--   * an audio URL column. Audio belongs to the show's host and is resolved from the
--     live feed at play time. Enclosure URLs rotate (tracking prefixes, dynamic ad
--     insertion), so a cached one is a dead play button.
--   * an updated-in-place migration path. The build always creates a fresh database
--     from curation/source/ and replays the `edits` table onto it.

PRAGMA foreign_keys = ON;

CREATE TABLE networks (
  id    INTEGER PRIMARY KEY,
  slug  TEXT NOT NULL UNIQUE,
  name  TEXT NOT NULL
);

CREATE TABLE shows (
  id              INTEGER PRIMARY KEY,
  slug            TEXT NOT NULL UNIQUE,
  title           TEXT NOT NULL,
  author          TEXT,
  network_id      INTEGER REFERENCES networks(id),
  -- Not plainly UNIQUE. Nine catalogued "shows" are really a limited series or season
  -- published inside a parent programme's feed, so they share the parent's feed_url.
  -- Merging them into arcs is a Phase 2 review call, so Phase 1 has to hold them.
  -- The partial unique index below keeps the invariant where it matters: at most one
  -- REVIEWED show per feed. A second one can only exist if it is flagged 'suspect'.
  feed_url        TEXT NOT NULL,
  home_url        TEXT,
  artwork_url     TEXT,
  lang            TEXT NOT NULL DEFAULT 'en',
  apple_category  TEXT,
  years           TEXT,
  -- The hand-written pitch for why this show is worth someone's time. Kept verbatim;
  -- it is the most valuable text in the catalog and no pipeline may rewrite it.
  why             TEXT,
  description     TEXT,
  -- 1 metadata+themes, 2 episodes labelled, 3 arcs, 4 subjects. The UI reads this and
  -- never offers what a show does not have.
  depth           INTEGER NOT NULL DEFAULT 1 CHECK (depth BETWEEN 1 AND 4),
  include_verdict TEXT NOT NULL DEFAULT 'unreviewed'
                  CHECK (include_verdict IN ('unreviewed','keep','cut','suspect'))
);

-- One feed, one show -- unless the extra entries are explicitly flagged for review.
-- This makes an undeclared duplicate impossible to insert while letting the nine known
-- ones through as 'suspect' until Phase 2 merges them into arcs.
CREATE UNIQUE INDEX shows_one_reviewed_per_feed
  ON shows (feed_url) WHERE include_verdict <> 'suspect';

CREATE TABLE arcs (
  id          INTEGER PRIMARY KEY,
  show_id     INTEGER NOT NULL REFERENCES shows(id),
  slug        TEXT NOT NULL,
  -- 'series' is a named run inside a feed (a season, a "Presents" drop); 'arc' is a
  -- shorter multi-episode story. Phase 1 only produces 'arc'.
  kind        TEXT NOT NULL CHECK (kind IN ('series','arc')),
  name        TEXT NOT NULL,
  description TEXT,
  confidence  TEXT NOT NULL DEFAULT 'low'
              CHECK (confidence IN ('low','medium','high','verified')),
  source      TEXT NOT NULL CHECK (source IN ('gold','segment','llm','human')),
  UNIQUE (show_id, slug)
);

CREATE TABLE episodes (
  id             INTEGER PRIMARY KEY,
  show_id        INTEGER NOT NULL REFERENCES shows(id),
  -- GUIDs are only unique within a feed, never globally.
  guid           TEXT NOT NULL,
  title          TEXT NOT NULL,
  -- The title with its arc/segment prefix stripped: "American Revolution | Saratoga | 4"
  -- has subject "Saratoga | 4".
  subject        TEXT,
  season         INTEGER,
  episode_number INTEGER,
  episode_type   TEXT,
  published_at   TEXT,
  description    TEXT,
  -- DISPLAY HINT ONLY. Cached so browse can say "6 parts, 4h 20m" without fetching 300
  -- feeds. Duration never changes once published, so caching is safe -- but the player
  -- still trusts the live feed. NULL until Phase 4 fetches it.
  duration_s     INTEGER,
  -- 0 when a background reconcile finds the episode gone from the feed. Never deleted:
  -- the themes and arcs attached to it are our work, not the publisher's.
  available      INTEGER NOT NULL DEFAULT 1 CHECK (available IN (0,1)),
  arc_id         INTEGER REFERENCES arcs(id),
  UNIQUE (show_id, guid)
);

CREATE INDEX episodes_by_show ON episodes (show_id, published_at DESC);
CREATE INDEX episodes_by_arc  ON episodes (arc_id);

CREATE TABLE themes (
  id          INTEGER PRIMARY KEY,
  slug        TEXT NOT NULL,
  tier        INTEGER NOT NULL CHECK (tier IN (1,2)),
  name        TEXT NOT NULL,
  description TEXT,
  parent_id   INTEGER REFERENCES themes(id),
  -- NOT unique on slug alone. Five slugs legitimately exist at both levels
  -- (political-scandal, institutional-coverup, police-misconduct, wrongful-conviction,
  -- family-secret) and a slug-only key would silently collapse them.
  UNIQUE (tier, slug),
  -- The two-tier promise, enforced by the database rather than by convention: a tier-2
  -- theme without a parent cannot be inserted.
  CHECK ((tier = 1 AND parent_id IS NULL) OR (tier = 2 AND parent_id IS NOT NULL))
);

CREATE TABLE people (
  id   INTEGER PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  role TEXT
);

CREATE TABLE subjects (
  id   INTEGER PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  kind TEXT CHECK (kind IN ('case','company','person','place','era','work'))
);

CREATE TABLE show_themes (
  show_id  INTEGER NOT NULL REFERENCES shows(id),
  theme_id INTEGER NOT NULL REFERENCES themes(id),
  PRIMARY KEY (show_id, theme_id)
);

CREATE TABLE episode_themes (
  episode_id INTEGER NOT NULL REFERENCES episodes(id),
  theme_id   INTEGER NOT NULL REFERENCES themes(id),
  role       TEXT NOT NULL CHECK (role IN ('primary','secondary')),
  confidence TEXT NOT NULL CHECK (confidence IN ('low','medium','high')),
  -- Votes agreeing. NULL for the 2026-07 Haiku run, which recorded agreement per show
  -- rather than per episode. Phase 3's relabel populates it.
  agreement  INTEGER,
  model      TEXT,
  run_id     TEXT,
  PRIMARY KEY (episode_id, theme_id)
);

CREATE INDEX episode_themes_by_theme ON episode_themes (theme_id, confidence);

-- The traversal layer. Entirely derived from the tables above, so it is always safe to
-- delete and rebuild.
CREATE TABLE edges (
  src_type TEXT NOT NULL,
  src_id   INTEGER NOT NULL,
  dst_type TEXT NOT NULL,
  dst_id   INTEGER NOT NULL,
  kind     TEXT NOT NULL,
  weight   REAL NOT NULL DEFAULT 1.0,
  -- The sentence the app shows when it explains a connection. Not decoration: if an
  -- edge cannot produce a sentence a person would accept, it should not exist.
  why      TEXT NOT NULL,
  PRIMARY KEY (src_type, src_id, dst_type, dst_id, kind)
);

CREATE INDEX edges_out ON edges (src_type, src_id, kind, weight DESC);
CREATE INDEX edges_in  ON edges (dst_type, dst_id, kind, weight DESC);

-- Append-only. Both the undo log and the few-shot example store that re-runs read so a
-- correction only has to be made once.
--
-- Rows key on entity_key, a STABLE string, never on the internal integer id. Every
-- build regenerates those integers from scratch, so an edit recorded against id 42
-- would silently land on a different row next time. entity_key formats:
--
--   show     <show-slug>
--   theme    <tier>:<theme-slug>          -- tier matters; 5 slugs exist at both
--   arc      <show-slug>/<arc-slug>
--   episode  <show-slug>/<guid>
--   catalog  ''                           -- build-wide notes, not replayable
CREATE TABLE edits (
  id          INTEGER PRIMARY KEY,
  at          TEXT NOT NULL,
  actor       TEXT NOT NULL,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('show','theme','arc','episode','catalog')),
  entity_key  TEXT NOT NULL,
  field       TEXT NOT NULL,
  before      TEXT,
  after       TEXT,
  note        TEXT
);

CREATE INDEX edits_by_entity ON edits (entity_type, entity_key, id);

CREATE TABLE releases (
  version       TEXT PRIMARY KEY,
  built_at      TEXT NOT NULL,
  show_count    INTEGER NOT NULL,
  episode_count INTEGER NOT NULL,
  -- SHA-256 over a canonically ordered dump, excluding built_at. Proves the data is
  -- reproducible; the file bytes are not expected to match.
  content_hash  TEXT NOT NULL,
  notes         TEXT
);

-- Contentless (content=''): the index is stored, the text is not. A hit gives back a
-- rowid, which IS the episode id, so callers join to `episodes` for anything they want
-- to display. Storing the text here too would duplicate 11 MB the catalog already has.
--
-- show_title is denormalized into the index so that searching "revisionist gladwell"
-- finds episodes of a show whose own title appears in neither the episode title nor its
-- description.
CREATE VIRTUAL TABLE search USING fts5(
  title,
  subject,
  description,
  show_title,
  content = '',
  tokenize = 'unicode61 remove_diacritics 2'
);
