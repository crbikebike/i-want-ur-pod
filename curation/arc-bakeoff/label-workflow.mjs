export const meta = {
  name: 'arc-gold-labeling',
  description: 'Dual independent Sonnet labelers + conservative reconciler produce ground-truth story arcs per feed',
  phases: [
    { title: 'Label', detail: 'two independent labelers per gold feed' },
    { title: 'Reconcile', detail: 'consensus arcs, precision-first' },
  ],
}

const A = typeof args === 'string' ? JSON.parse(args) : args
const slugs = A.slugs
const goldDir = A.goldDir

const ARC_SCHEMA = {
  type: 'object',
  properties: {
    arcs: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string', description: 'The story arc / season name' },
          member_guids: { type: 'array', items: { type: 'string' } },
        },
        required: ['name', 'member_guids'],
      },
    },
  },
  required: ['arcs'],
}

const DEFINITION = `A "story arc" is a set of TWO OR MORE episodes that the show deliberately built as one
multi-part story or season about a single subject, event, person, or case — meant to be heard together
and in order (e.g. a 5-part series on the American Revolution, a 3-part investigation of one cold case,
a serialized season).

COUNT as one arc:
- Explicit multi-parters: "X | Title | 1..N", "X - Part 1..N", "Chapter 1..N", "(Part N)", "- Ep. N".
- A run of episodes clearly continuing one narrative even if numbering is loose, AS LONG AS the shared
  subject is unmistakable from the titles.
- A tagged season (itunes:season) whose episodes clearly form one continuous story.

Do NOT count:
- Standalone one-off episodes; trailers/teasers/bonus/Q&A unless they are part of the numbered run.
- Episodes that merely share a word or format but are separate stories (e.g. an interview show where every
  episode is a different guest — that is NOT an arc).
- Two unrelated episodes grouped just because titles look similar.

PRECISION FIRST: when unsure whether episodes truly belong together, leave them OUT. A missed arc is far
better than a wrong grouping. Only include a member GUID you are confident belongs to that arc.`

async function label(slug, which) {
  const prompt = `You are labeling GROUND TRUTH story arcs for one podcast feed. This is pass "${which}".

${DEFINITION}

Read the feed file at: ${goldDir}/${slug}.json
It contains {slug, title, episodes:[{guid, title, season, episodeNumber, episodeType, iso}]} newest-first.

Identify every genuine story arc. For each, give a short human name and the exact list of member "guid" values
(copied verbatim from the file). Return ONLY arcs with 2+ members. Ignore singles.`
  return agent(prompt, { label: `label:${slug}:${which}`, phase: 'Label',
    agentType: 'general-purpose', model: 'sonnet', schema: ARC_SCHEMA })
}

async function reconcile(slug, a, b) {
  const prompt = `Two independent annotators labeled the story arcs of one podcast feed. Produce the CONSENSUS.

${DEFINITION}

Read the feed file at: ${goldDir}/${slug}.json (episodes with their guids).

Annotator A arcs:
${JSON.stringify(a?.arcs ?? [], null, 1)}

Annotator B arcs:
${JSON.stringify(b?.arcs ?? [], null, 1)}

Rules for the consensus, precision-first:
- Keep an arc only if it is clearly a real multi-part story (both annotators found it, OR one found it and it
  is unambiguously correct from the titles).
- For a kept arc, include a guid as a member only if it clearly belongs (prefer the intersection; add a guid
  only when obviously part of the run).
- Drop anything doubtful. Merge duplicates that are the same arc under different names.
Return the final consensus arcs (2+ members each), member_guids copied verbatim from the file.`
  return agent(prompt, { label: `reconcile:${slug}`, phase: 'Reconcile',
    agentType: 'general-purpose', model: 'sonnet', schema: ARC_SCHEMA })
}

const labeled = await pipeline(
  slugs,
  (slug) => parallel([
    () => label(slug, 'A'),
    () => label(slug, 'B'),
  ]).then(([a, b]) => ({ slug, a, b })),
  ({ slug, a, b }) => reconcile(slug, a, b).then((final) => ({ slug, arcs: final?.arcs ?? [] })),
)

const out = {}
for (const r of labeled.filter(Boolean)) {
  out[r.slug] = (r.arcs || []).map(a => ({ name: a.name, members: a.member_guids }))
}
return out
