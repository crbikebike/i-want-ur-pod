-- When a show was last read for story arcs, and what came of it.
--
-- Needed because "no arcs here" is a real answer that must survive. Two thirds of the
-- shows a model will read are anthologies or interview shows where every episode stands
-- alone, and without somewhere to record that, the next pass reads them all again -- the
-- same loop the arc-naming queue hit, where a decision that produced no row left nothing
-- to exclude on.
--
-- Mirrors shows.fit_checked_at, which does the same job for the inclusion question.
-- Phase 4's comber reads both to find the longest-unchecked shows rather than re-walking
-- all 275 every night.

ALTER TABLE shows ADD COLUMN arcs_checked_at TEXT;
ALTER TABLE shows ADD COLUMN arcs_checked_by TEXT;
-- How many episodes the reader actually saw. A show with 566 episodes is read in part,
-- and a later pass has to be able to tell "found nothing in all of it" from "found
-- nothing in the half we looked at".
ALTER TABLE shows ADD COLUMN arcs_checked_eps INTEGER;

CREATE INDEX IF NOT EXISTS shows_needing_arcs
  ON shows (arcs_checked_at) WHERE deleted_at IS NULL AND include_verdict = 'keep';
