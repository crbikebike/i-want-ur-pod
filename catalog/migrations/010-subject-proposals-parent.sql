-- A proposed subject needs a parent theme and a slug, like a real one.
--
-- The proposals table was built for slugs a labelling run reached for and could not have.
-- Splitting a theme is the same shape from the other direction: a pass reads the episodes
-- already sitting under one overloaded subject and proposes the distinctions that would
-- separate them. Both end up in front of a person, so both live here.
--
-- Why this is needed at all: two pilots measured it. 99% Invisible put 82 of 100 episodes
-- on one subject, because `design-and-architecture` is the only slug in the whole 148
-- aimed at the built environment -- urban planning, product design, typography, sound
-- design and structural engineering share one bucket, where true crime has a dozen.
-- Swindled, on a well-served part of the vocabulary, used ~30 distinct subjects across
-- 100 episodes and found one specific hole. Uneven depth, not bad vocabulary.

ALTER TABLE subject_proposals ADD COLUMN theme_id INTEGER REFERENCES themes(id);
ALTER TABLE subject_proposals ADD COLUMN slug TEXT;
-- Which existing subject this is carved out of, when it is a split rather than a gap.
-- Accepting one means the episodes under the parent need re-reading, and that is only
-- knowable if the relationship is recorded.
ALTER TABLE subject_proposals ADD COLUMN splits_from INTEGER REFERENCES subjects(id);

CREATE INDEX IF NOT EXISTS subject_proposals_waiting
  ON subject_proposals (theme_id) WHERE resolved_at IS NULL;
