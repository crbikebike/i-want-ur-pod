export const meta = {
  name: 'arc-junk-adjudication',
  description: 'Two blind Sonnet judges + reconciler rule each junk arc REAL (labeler miss) or JUNK (not a narrative arc)',
  phases: [
    { title: 'Judge', detail: 'two independent verdicts per junk arc' },
    { title: 'Reconcile', detail: 'final REAL/JUNK verdict + corrected members' },
  ],
}

const A = typeof args === 'string' ? JSON.parse(args) : args
const candidates = A.candidates
const goldDir = A.goldDir

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['REAL', 'JUNK'] },
    member_guids: { type: 'array', items: { type: 'string' },
      description: 'If REAL: the exact episode guids that form the arc (copy verbatim from the feed). If JUNK: []' },
    reason: { type: 'string', description: 'One sentence, by the definition' },
    guard_hint: { type: 'string',
      description: 'If JUNK: a GENERAL structural signal that marks this as a non-narrative series (no show names)' },
  },
  required: ['verdict', 'member_guids', 'reason', 'guard_hint'],
}

const DEFINITION = `A "story arc" is TWO OR MORE episodes the show deliberately built as ONE multi-part story about a
single subject, event, person, or case — meant to be heard together, in order (a 5-part series on one war,
a 3-part investigation of one case, a serialized season telling one story).

REAL (belongs in ground truth): explicit multi-parters on ONE subject — "X | title | 1..N", "X - Part 1..N",
"X (Part 1..N)", "#1..N" on one continuing subject, a serialized season that tells one story. Encore/Fan-Favorite
RE-RUNS of a genuine multi-part series still count as a real arc.

JUNK (NOT a story arc): an ANTHOLOGY or RECURRING SEGMENT where each numbered entry is a DIFFERENT, standalone
topic ("Mini-Stories: Volume 22" then "Volume 21" — different unrelated stories each time; "Catch a Kite 8, 7" —
a recurring mailbag segment); a GENERIC whole-season bucket ("Season 2 Ep 170, 169…") that is just the show's
normal episodes; or a coincidental grouping of unrelated episodes that merely share a word. A counter number
alone does NOT make it an arc — the episodes must tell ONE continuing story.

PRODUCT CLARIFICATION (important): the goal is a "Story arcs" shelf with an "Add all N" button — a listener
binges the run in order. So a BOUNDED, numbered mini-series under one series title, numbered 1..N, that a show
deliberately produced and released as a block, DOES count as a REAL arc EVEN IF each numbered part profiles a
DIFFERENT instance of the theme (e.g. "Daring Prison Escapes | <different escape> | 1..5", "First Ladies |
<different first lady> | 1..6"). What is still JUNK is an OPEN-ENDED recurring segment/format that reappears
indefinitely across the feed with an ever-climbing counter, each entry an unrelated subject ("Diss & Tell |
<different feud> | 218" appearing again at 217, 190, 150… — a format, not a block). The test: a bounded block
released together = REAL; an open-ended recurring format = JUNK.`

function judgePrompt(c, which) {
  return `Rule whether a candidate episode grouping is a REAL story arc or JUNK. This is blind pass "${which}" —
decide only by the definition, nothing else.

${DEFINITION}

Read the feed at: ${goldDir}/${c.slug}.json  (episodes with guids, titles, season, episodeType).

Candidate grouping "${c.name}" — its episode titles:
${c.titles.map((t, i) => `  ${i + 1}. ${t}`).join('\n')}
Candidate member guids (in the same order):
${JSON.stringify(c.members)}

Using the full feed for context, decide:
- REAL → these episodes truly form ONE multi-part story. Return member_guids = the exact guids that belong
  (usually the candidate's, but drop any that don't fit and add any obviously-missing sibling from the feed).
- JUNK → this is an anthology / recurring segment / generic-season / coincidental grouping, not one story.
  Return member_guids = [] and a GENERAL guard_hint (a structural signal, no show-specific names).`
}

function reconcilePrompt(c, a, b) {
  return `Two blind annotators judged whether a candidate grouping is a REAL story arc or JUNK. Give the final verdict.

${DEFINITION}

Read the feed at: ${goldDir}/${c.slug}.json

Candidate "${c.name}" titles:
${c.titles.map((t, i) => `  ${i + 1}. ${t}`).join('\n')}
guids: ${JSON.stringify(c.members)}

Annotator A: ${JSON.stringify(a)}
Annotator B: ${JSON.stringify(b)}

Decide conservatively and precisely:
- REAL only if it is unmistakably ONE multi-part story (both agree, or one is clearly right). Return the exact
  correct member_guids.
- JUNK otherwise (anthology / recurring segment / generic season / coincidental). Return [] and a general guard_hint.`
}

const judged = await pipeline(
  candidates,
  (c) => parallel([
    () => agent(judgePrompt(c, 'A'), { label: `judge:${c.id}:A`, phase: 'Judge',
      agentType: 'general-purpose', model: 'sonnet', schema: VERDICT_SCHEMA }),
    () => agent(judgePrompt(c, 'B'), { label: `judge:${c.id}:B`, phase: 'Judge',
      agentType: 'general-purpose', model: 'sonnet', schema: VERDICT_SCHEMA }),
  ]).then(([a, b]) => ({ c, a, b })),
  ({ c, a, b }) => agent(reconcilePrompt(c, a, b), { label: `reconcile:${c.id}`, phase: 'Reconcile',
    agentType: 'general-purpose', model: 'sonnet', schema: VERDICT_SCHEMA })
    .then((f) => ({ id: c.id, slug: c.slug, name: c.name,
      verdict: f?.verdict ?? 'JUNK', members: f?.member_guids ?? [],
      reason: f?.reason ?? '', guard_hint: f?.guard_hint ?? '',
      votes: [a?.verdict, b?.verdict] })),
)

return judged.filter(Boolean)
