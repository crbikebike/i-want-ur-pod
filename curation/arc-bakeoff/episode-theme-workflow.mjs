export const meta = {
  name: 'episode-theme-taxonomy',
  description: 'Open-code, consolidate, then assign an episode-level theme taxonomy for an anthology show',
  phases: [
    { title: 'Open coding', detail: 'free-form themes per episode, no fixed vocabulary yet' },
    { title: 'Consolidate', detail: 'one pass over every raw label -> a controlled vocabulary' },
    { title: 'Assign', detail: 'each episode gets one primary + up to two secondary' },
    { title: 'Agreement', detail: 'second assignment pass, different batching, to measure ambiguity' },
  ],
}

const A = typeof args === 'string' ? JSON.parse(args) : args
const slug = A.slug
const total = A.count                    // episode count, so batches can be planned
const file = `curation/arc-bakeoff/episode-themes/_input-${slug}.json`

const OPEN_SCHEMA = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          i: { type: 'integer', description: 'the episode index, copied exactly' },
          theme: { type: 'string', description: 'a short free-form theme phrase, 2-5 words' },
          rationale: { type: 'string', description: 'one line on why' },
        },
        required: ['i', 'theme', 'rationale'],
      },
    },
  },
  required: ['items'],
}

const VOCAB_SCHEMA = {
  type: 'object',
  properties: {
    vocabulary: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          slug: { type: 'string', description: 'kebab-case identifier' },
          name: { type: 'string', description: 'short human name, title case' },
          definition: { type: 'string', description: 'one sentence: what belongs here and what does not' },
          mapsTo: { type: 'string', description: 'an existing show-level theme slug, or empty string if none fits' },
        },
        required: ['slug', 'name', 'definition', 'mapsTo'],
      },
    },
  },
  required: ['vocabulary'],
}

const ASSIGN_SCHEMA = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          i: { type: 'integer' },
          primary: { type: 'string', description: 'exactly one vocabulary slug' },
          secondary: { type: 'array', items: { type: 'string' }, description: 'zero to two other vocabulary slugs' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['i', 'primary', 'secondary', 'confidence'],
      },
    },
  },
  required: ['items'],
}

const FILE_NOTE = `The file ${file} holds {slug, title, episodes:[{i, guid, display, subject, iso, type}]}.
"display" is the show's own poetic episode name; "subject" is the real-world company, person or
event the episode is about. The subject is what matters — use what you know about it.`

/* ---------- pass 1: open coding ---------- */
function openCode(lo, hi) {
  return agent(
    `You are building a theme taxonomy for one podcast's back catalogue, starting with open coding.

${FILE_NOTE}

Read the file and handle ONLY episodes with i from ${lo} to ${hi - 1} inclusive.

For each, name the underlying theme — the kind of story it is, not the specific subject.
"Ford Pinto" and "OceanGate" are both a company shipping something it knew was unsafe.
"Bre-X" and "Theranos" are both a company faking the thing it claimed to have.

Give a short theme phrase (2-5 words) and one line of reasoning. Do NOT use a fixed list —
these labels get consolidated later, so say what is actually there. If you do not recognise the
subject, infer from the wording and mark that in the rationale.`,
    { label: `open:${lo}-${hi}`, phase: 'Open coding', model: 'sonnet', schema: OPEN_SCHEMA })
}

/* ---------- pass 2: consolidate ---------- */
function consolidate(raw, showThemes) {
  return agent(
    `Consolidate these free-form episode labels into a real taxonomy.

Here are ${raw.length} episode labels from one podcast's back catalogue:

${raw.map(r => `  ${r.i}. ${r.theme} — ${r.rationale}`).join('\n')}

Produce a controlled vocabulary of 10 to 16 themes covering all of them. Rules:

- Every theme must plausibly hold at least 3 of these episodes. Fewer than that is a label, not
  a category — merge it into a neighbour.
- No theme may hold more than about a third of the catalogue. If one would, split it along the
  distinction that actually matters to a listener choosing what to hear next.
- Themes must be distinguishable. If you cannot write a sentence saying what belongs in A and
  not in B, they are one theme.
- The definition must say what belongs AND what does not. That sentence is what a later pass
  uses to assign episodes, so vagueness there becomes noise everywhere.
- Prefer the distinction a listener would care about over an academic one.

For each theme also set "mapsTo": the slug of an existing show-level theme it corresponds to, or
"" when none genuinely fits. Do not force a mapping. The existing show-level themes are:

${showThemes}`,
    { label: 'consolidate', phase: 'Consolidate', model: 'sonnet', schema: VOCAB_SCHEMA })
}

/* ---------- pass 3: assign ---------- */
function assign(vocab, lo, hi, run) {
  const list = vocab.map(v => `  ${v.slug} — ${v.name}: ${v.definition}`).join('\n')
  return agent(
    `Assign themes to podcast episodes from a FIXED vocabulary. Do not invent themes.

${FILE_NOTE}

Read the file and handle ONLY episodes with i from ${lo} to ${hi - 1} inclusive.

The vocabulary, which is closed:

${list}

For each episode give exactly one "primary" — the single best home for it — and zero to two
"secondary" slugs for genuine overlaps. Never repeat the primary in secondary. Use only slugs
from the list above, spelled exactly. Set confidence to low when the subject is unfamiliar to
you or two themes fit equally well.`,
    { label: `assign${run}:${lo}-${hi}`, phase: run === 2 ? 'Agreement' : 'Assign',
      model: 'haiku', schema: ASSIGN_SCHEMA })
}

/* ---------- run ---------- */
function batches(n, size) {
  const out = []
  for (let lo = 0; lo < n; lo += size) out.push([lo, Math.min(n, lo + size)])
  return out
}

phase('Open coding')
const coded = await parallel(batches(total, 40).map(([lo, hi]) => () => openCode(lo, hi)))
const raw = coded.filter(Boolean).flatMap(r => r.items || [])
log(`open-coded ${raw.length}/${total} episodes`)

phase('Consolidate')
const SHOW_THEMES = A.showThemes || ''
const vocabRes = await consolidate(raw, SHOW_THEMES)
const vocabulary = (vocabRes?.vocabulary || []).map(v => ({ ...v, mapsTo: v.mapsTo || null }))
log(`vocabulary: ${vocabulary.length} themes — ${vocabulary.map(v => v.slug).join(', ')}`)

/* Two assignment passes at different batch sizes, so episodes sit beside different
   neighbours each time. Where the runs disagree, the vocabulary is ambiguous there —
   that number is the real measure of the taxonomy, not the audit. */
phase('Assign')
const runA = await parallel(batches(total, 40).map(([lo, hi]) => () => assign(vocabulary, lo, hi, 1)))
phase('Agreement')
const runB = await parallel(batches(total, 51).map(([lo, hi]) => () => assign(vocabulary, lo, hi, 2)))

const flat = rs => {
  const m = {}
  for (const r of rs.filter(Boolean)) for (const it of r.items || []) m[it.i] = it
  return m
}
const A1 = flat(runA), B1 = flat(runB)
let same = 0, compared = 0
for (const i of Object.keys(A1)) {
  if (B1[i]) { compared++; if (A1[i].primary === B1[i].primary) same++ }
}
const agreement = compared ? same / compared : 0
log(`primary agreement across the two runs: ${(agreement * 100).toFixed(1)}% of ${compared}`)

return {
  models: { openCoding: 'sonnet', consolidate: 'sonnet', assign: 'haiku' },
  vocabulary,
  assignments: Object.values(A1),
  agreement: { runs: 2, compared, primaryAgreement: Number(agreement.toFixed(4)) },
}
