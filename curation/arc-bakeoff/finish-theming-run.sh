#!/usr/bin/env bash
# Turn whatever the assign pass has produced into the committed artifacts.
#
# Safe to run at ANY coverage. finalize reports unassigned episodes rather than
# failing, so a partial run still yields a browsable index -- it just says so.
# Re-run it as more batches land; it rebuilds from scratch each time.
set -euo pipefail

cd "$(dirname "$0")"
ARC="$PWD"
ROOT="$(cd ../.. && pwd)"
VOCAB="$ARC/episode-themes/_vocabulary-draft.json"

[ -f "$VOCAB" ] || { echo "no vocabulary at $VOCAB"; exit 1; }

batches=$(ls episode-themes/_work/assign/*.tsv 2>/dev/null | wc -l)
rows=$(cat episode-themes/_work/assign/*.tsv 2>/dev/null | grep -vc '^#' || true)
echo "=== assign output: $batches batches, $rows labelled rows ==="
echo

echo "=== finalize ==="
python3 build-episode-themes.py finalize --vocab "$VOCAB"
echo

echo "=== catalog index ==="
python3 build-catalog-index.py
echo

echo "=== verification ==="
python3 - <<'PY'
import json, pathlib, collections
ET = pathlib.Path("episode-themes")
rep = json.loads((ET / "_run-report.json").read_text())
vocab = json.loads((ET / "_vocabulary.json").read_text())["themes"]

print(f"shows            {rep['shows']}")
print(f"episodes labelled{rep['episodesLabelled']:>8,}")
print(f"unassigned       {rep['unassigned']:>8,}")
print(f"vocabulary       {rep['vocabularySize']} themes "
      f"({rep['showSpecificThemes']} used by one show)")

ag = (rep.get("agreement") or {}).get("_overall")
if ag:
    print(f"two-run agreement {ag['primaryAgreement']:.1%} over {ag['compared']} episodes")

# The check that matters: a theme living in one show is a per-show vocabulary that
# leaked through. Cross-show reach is the whole point of the index.
multi = [v for v in vocab if v["showCount"] >= 3 and v["episodeCount"]]
used = [v for v in vocab if v["episodeCount"]]
print(f"themes in use    {len(used)}/{len(vocab)}")
print(f"  spanning 3+ shows {len(multi)} ({len(multi)/max(1,len(used)):.0%} of used)")

conf = collections.Counter()
for s in rep["showReports"]:
    conf.update(s["confidence"])
tot = sum(conf.values()) or 1
print("confidence per application: " + "  ".join(
    f"{k or '?'} {v:,} ({v/tot:.0%})" for k, v in conf.most_common()))

flagged = [s for s in rep["showReports"] if s["auditFlags"]]
print(f"shows flagged by audit {len(flagged)}")
for s in flagged[:5]:
    print(f"   {s['slug']}: {s['auditFlags'][0]}")

print("\ntop themes by episode count:")
for v in vocab[:10]:
    print(f"   {v['episodeCount']:>6,}  {v['showCount']:>3} shows  {v['name']}")
PY

echo
echo "=== detector untouched ==="
python3 score.py 2>/dev/null | grep -E "A8-cascade" || echo "(score.py produced no A8 line — check manually)"
