"""The committed subject->theme mapping must stay valid against the source vocabulary.

subject-themes.json is authored by hand (by a model, reviewed by a human in Phase 2).
That makes it data, not code -- so it needs a test that catches drift when the source
vocabulary changes underneath it.
"""

import json
from collections import Counter
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "curation/source"
MAPPING = ROOT / "catalog/build/subject-themes.json"

VALID_CONFIDENCE = {"high", "medium", "low"}


@pytest.fixture(scope="module")
def data():
    themes = {t["slug"] for t in json.loads((SRC / "themes.json").read_text())}
    vocab = json.loads((SRC / "episode-themes/_vocabulary.json").read_text())["themes"]
    mapping = json.loads(MAPPING.read_text())
    needs = [
        t["slug"] for t in vocab if not t.get("relatedShowThemes") and t["slug"] not in themes
    ]
    return {
        "themes": themes,
        "vocab": {t["slug"]: t for t in vocab},
        "rows": mapping["subjects"],
        "needs": set(needs),
    }


def test_covers_exactly_the_subjects_that_need_a_theme(data):
    mapped = {r["slug"] for r in data["rows"]}
    assert mapped == data["needs"], (
        f"missing: {sorted(data['needs'] - mapped)}  "
        f"extra: {sorted(mapped - data['needs'])}"
    )


def test_every_theme_is_one_of_the_thirty(data):
    bad = [(r["slug"], r["theme"]) for r in data["rows"] if r["theme"] not in data["themes"]]
    assert bad == []


def test_every_subject_exists_in_the_vocabulary(data):
    bad = [r["slug"] for r in data["rows"] if r["slug"] not in data["vocab"]]
    assert bad == []


def test_confidences_are_valid(data):
    bad = [(r["slug"], r["confidence"]) for r in data["rows"] if r["confidence"] not in VALID_CONFIDENCE]
    assert bad == []


def test_no_subject_is_mapped_twice(data):
    dupes = [s for s, n in Counter(r["slug"] for r in data["rows"]).items() if n > 1]
    assert dupes == []


def test_low_confidence_rows_say_why(data):
    """A forced mapping without a reason is indistinguishable from a careless one."""
    silent = [r["slug"] for r in data["rows"] if r["confidence"] == "low" and not r.get("note")]
    assert silent == []


def test_no_theme_is_overloaded(data):
    """Sanity bound from the spec. A theme swallowing everything means the 30 need work.

    This is intentionally generous -- it catches a mapping bug, not a taste disagreement.
    """
    counts = Counter(r["theme"] for r in data["rows"])
    overloaded = {p: n for p, n in counts.items() if n > 20}
    assert overloaded == {}, f"themes with too many authored subjects: {overloaded}"
