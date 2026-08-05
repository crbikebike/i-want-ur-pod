# Escalation Voter Brief

**Before your first batch, read `docs/briefs/corrections.md` if it has entries.** Those are human verdicts on machine labels -- where a person overrode the machine, the override names a mistake your read should not repeat.


You are one of three independent voters on a slice of the doubt set — episodes whose
label was a low-confidence guess or a structural one-off. Your vote is one subject slug
per episode. Two other voters are reading the same episodes; none of you sees the
others' votes, and none of you sees the current label. That blindness is the point:
`agreement` only means something if the reads are independent.

## Setup

    cd /home/hf/claude/i-want-ur-pod
    python3 -m admin.api.label vocab        # the 199 subjects. Read it properly.

The manifest and votes directory are given in your launch prompt, along with your slice
number, voter letter (a, b or c) and page range.

## Per page

    python3 -m admin.api.escalate page <manifest> --slice <N> --page <K>

Read every episode — title, date, description, show context, arc. Pick the one subject
whose definition fits best as **primary**. The definitions carry `Not:` clauses; they
are the boundary lines, use them.

Write `<votes-dir>/v<slice>-<voter>-p<page>.json`:

    {"votes": {"8": "design-and-architecture", "1136": "heist-and-robbery"}}

Every episodeId on the page gets a vote. There is no abstain — if nothing fits well,
vote for the least-wrong subject anyway; a genuine misfit will show up as three voters
scattering, which is exactly the signal the tally reads. Keys are episode ids as
strings, values are subject slugs, nothing else.

## Rules

- One page file per page, exactly the naming above. Never overwrite another voter's
  file — your voter letter is in the name, keep it right.
- Do not query the database for existing labels, and do not read other vote files.
  You are blind by design.
- Work your assigned page range in order. Stop after your last page and report: pages
  voted, and any episode where the vocabulary had no defensible home (show + episodeId +
  what was missing). Those reports feed the correction loop.
