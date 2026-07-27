-- Whether a show is the kind of thing this catalog is for.
--
-- The premise is narrow on purpose: story-driven, investigative, produced. Not a host
-- and a guest talking. 300-odd shows were imported from an earlier list and never
-- checked against that, which makes "never reviewed" the most common thing in the queue
-- and the least interesting -- it is the same question 300 times, and a model can answer
-- most of them.
--
-- This holds the assessment, not the decision. include_verdict stays the human's. A
-- confident assessment can settle itself through auto.py; an unsure one becomes a card
-- with the reasoning already on it, which is a much faster read than judging cold.

ALTER TABLE shows ADD COLUMN fit_verdict TEXT;      -- narrative | talk | mixed | unclear
ALTER TABLE shows ADD COLUMN fit_confidence TEXT;   -- high | medium | low
ALTER TABLE shows ADD COLUMN fit_reason TEXT;       -- one sentence, shown on the card
ALTER TABLE shows ADD COLUMN fit_checked_at TEXT;
ALTER TABLE shows ADD COLUMN fit_model TEXT;

CREATE INDEX shows_needing_fit
  ON shows (fit_checked_at) WHERE deleted_at IS NULL;
