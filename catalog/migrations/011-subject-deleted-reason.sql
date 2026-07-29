-- A retired subject has to say why it was retired.
--
-- `arcs` and `episodes` both carry `deleted_reason` next to `deleted_at`; `subjects` only
-- ever got the timestamp, so the one door could soft-delete a subject and had nowhere to
-- record the argument for it. That is the wrong way round. A subject is browsable
-- vocabulary -- retiring one changes what a listener can navigate by, and it is the kind
-- of decision someone will want to reverse or defend six months later.
--
-- Found while retiring `music-scene-history`, a near-duplicate of `music-scene-movement`
-- in the same theme. Two labelling agents independently reported they could not tell the
-- two apart, and one named the consequence exactly: two agents labelling the same episode
-- differently would show up as *disagreement* in the agreement metric rather than as the
-- vocabulary fault it actually is. That reasoning is what belongs in the column.

ALTER TABLE subjects ADD COLUMN deleted_reason TEXT;
