-- Candidate feeds waiting on a human, for rows that point at the wrong podcast.
--
-- Twenty-seven rows serve a different show than they claim, and the automation that finds
-- replacements is right about two thirds of the time. That is good enough to *propose*
-- and nowhere near good enough to *apply*: the three signals available are a title (which
-- is the thing that collided), a publisher name the curator wrote as prose, and a network
-- that may have changed since. Tightening the scoring traded a false positive for a false
-- negative three times running.
--
-- So the confident ones are confirmed by reading the feed, and everything fuzzy lands
-- here as a card. The evidence travels with the proposal -- the feed's own title, its
-- publisher, and a handful of real episode titles -- because that is what settles it.
-- "7 Hebrew Words for Praise" against "a true-crime docuseries about April Balascio" is
-- not a close call once both are on the screen.
--
-- Workbench-owned, like `runs`: no catalog entity lives here, so it is written directly.
-- Confirming one is what goes through edits.apply().

CREATE TABLE IF NOT EXISTS feed_proposals (
  id            INTEGER PRIMARY KEY,
  show_id       INTEGER NOT NULL REFERENCES shows(id),
  feed_url      TEXT    NOT NULL,
  feed_title    TEXT,
  feed_author   TEXT,
  episode_count INTEGER,
  image_url     TEXT,
  -- A JSON array of real episode titles. The single most useful thing on the card, and
  -- the reason this table stores evidence rather than just a URL: re-fetching every feed
  -- to render a queue would make the queue unusable.
  sample        TEXT,
  -- 'podcastindex' | 'apple'. Neither source is complete -- The Clearing is in Apple with
  -- no feed URL and absent from the dump entirely -- so knowing which found it is worth
  -- keeping.
  source        TEXT,
  -- What the machine thought, kept for calibration rather than for deciding.
  title_score     REAL,
  publisher_score REAL,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  -- NULL while waiting. 'confirmed' | 'rejected'. Never deleted, so a rejected candidate
  -- is not proposed again next pass.
  resolved_at   TEXT,
  resolved_as   TEXT CHECK (resolved_as IN ('confirmed', 'rejected')),
  UNIQUE (show_id, feed_url)
);

CREATE INDEX IF NOT EXISTS feed_proposals_waiting
  ON feed_proposals (show_id) WHERE resolved_at IS NULL;
