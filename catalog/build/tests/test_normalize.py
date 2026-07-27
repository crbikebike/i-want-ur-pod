"""Tests for the pure helpers the migration leans on.

These are the functions where a quiet bug costs the most: `feed_url` normalization is
the join key between catalog.json and every other source file, so getting it wrong
silently drops shows rather than raising.
"""

import pytest

from catalog.build import normalize as n


# --- feed_url normalization -----------------------------------------------------


def test_identical_urls_agree():
    assert n.normalize_feed_url("https://example.com/feed.rss") == n.normalize_feed_url(
        "https://example.com/feed.rss"
    )


def test_host_case_is_ignored():
    assert n.normalize_feed_url("https://Example.COM/feed.rss") == n.normalize_feed_url(
        "https://example.com/feed.rss"
    )


def test_path_case_is_preserved():
    """Podcast hosts serve case-sensitive paths; folding them would merge real feeds."""
    assert n.normalize_feed_url("https://example.com/Feed.rss") != n.normalize_feed_url(
        "https://example.com/feed.rss"
    )


def test_trailing_slash_is_ignored():
    assert n.normalize_feed_url("https://example.com/feed/") == n.normalize_feed_url(
        "https://example.com/feed"
    )


def test_repeated_trailing_slashes_are_ignored():
    assert n.normalize_feed_url("https://example.com/feed///") == n.normalize_feed_url(
        "https://example.com/feed"
    )


def test_a_bare_host_survives_slash_stripping():
    assert n.normalize_feed_url("https://example.com/") == "https://example.com/"


def test_tracking_params_are_dropped():
    assert n.normalize_feed_url(
        "https://example.com/feed.rss?utm_source=apple&utm_medium=podcast"
    ) == n.normalize_feed_url("https://example.com/feed.rss")


def test_meaningful_params_are_kept():
    """Plenty of feeds carry a required auth or id param. Dropping it breaks the feed."""
    kept = n.normalize_feed_url("https://example.com/feed?id=42")
    assert "id=42" in kept


def test_remaining_params_are_sorted_for_stability():
    assert n.normalize_feed_url("https://example.com/f?b=2&a=1") == n.normalize_feed_url(
        "https://example.com/f?a=1&b=2"
    )


def test_scheme_differences_are_not_collapsed():
    """http and https are different endpoints; treat them as different until proven equal."""
    assert n.normalize_feed_url("http://example.com/f") != n.normalize_feed_url(
        "https://example.com/f"
    )


def test_whitespace_is_stripped():
    assert n.normalize_feed_url("  https://example.com/f  ") == n.normalize_feed_url(
        "https://example.com/f"
    )


@pytest.mark.parametrize("bad", ["", "   ", None])
def test_empty_input_raises(bad):
    with pytest.raises(ValueError):
        n.normalize_feed_url(bad)


# --- slugify --------------------------------------------------------------------


@pytest.mark.parametrize(
    "title,expected",
    [
        ("Revisionist History", "revisionist-history"),
        ("99% Invisible", "99-invisible"),
        ("S-Town", "s-town"),
        ("The Dream: Season 2", "the-dream-season-2"),
        ("Alice Isn't Dead", "alice-isn-t-dead"),
        ("  Padded  ", "padded"),
        ("Multiple   Spaces", "multiple-spaces"),
        ("Trailing---Dashes---", "trailing-dashes"),
    ],
)
def test_slugify(title, expected):
    assert n.slugify(title) == expected


def test_slugify_matches_the_existing_corpus_conventions():
    """These slugs already exist in curation/source/ and must not change."""
    assert n.slugify("99% Invisible") == "99-invisible"
    assert n.slugify("Alice Isn't Dead") == "alice-isn-t-dead"
    assert n.slugify("13 Minutes to the Moon") == "13-minutes-to-the-moon"


def test_slugify_handles_accents():
    assert n.slugify("Se Regalan Dudas") == "se-regalan-dudas"
    assert n.slugify("Transfert — Épisode") == "transfert-episode"


def test_slugify_rejects_a_title_with_no_usable_characters():
    with pytest.raises(ValueError):
        n.slugify("!!!")


# --- display splitting ----------------------------------------------------------


def test_split_display_pulls_the_segment_prefix():
    seg, subject = n.split_display("American Revolution | Saratoga | 4")
    assert seg == "American Revolution"
    assert subject == "Saratoga | 4"


def test_split_display_returns_no_segment_when_there_is_no_separator():
    seg, subject = n.split_display("The Original 100 Objects")
    assert seg is None
    assert subject == "The Original 100 Objects"


def test_split_display_trims_whitespace_around_the_separator():
    seg, subject = n.split_display("Empire   |   The Raj")
    assert seg == "Empire"
    assert subject == "The Raj"


def test_split_display_ignores_an_empty_prefix():
    seg, subject = n.split_display(" | Orphaned")
    assert seg is None
    assert subject == "Orphaned"


# --- similarity -----------------------------------------------------------------


def test_jaccard_identical_sets():
    assert n.jaccard({"a", "b"}, {"a", "b"}) == 1.0


def test_jaccard_disjoint_sets():
    assert n.jaccard({"a"}, {"b"}) == 0.0


def test_jaccard_partial_overlap():
    assert n.jaccard({"a", "b"}, {"b", "c"}) == pytest.approx(1 / 3)


def test_jaccard_empty_sets_are_not_similar():
    """Two shows with no themes share nothing. 0/0 must not become 1.0."""
    assert n.jaccard(set(), set()) == 0.0


def test_cosine_identical_vectors():
    assert n.cosine({"a": 3, "b": 4}, {"a": 3, "b": 4}) == pytest.approx(1.0)


def test_cosine_ignores_magnitude():
    """A 700-episode show and a 6-episode show with the same mix must read as similar."""
    assert n.cosine({"a": 1, "b": 2}, {"a": 50, "b": 100}) == pytest.approx(1.0)


def test_cosine_orthogonal_vectors():
    assert n.cosine({"a": 1}, {"b": 1}) == 0.0


def test_cosine_empty_vector():
    assert n.cosine({}, {"a": 1}) == 0.0


def test_cosine_partial_overlap_is_between():
    v = n.cosine({"a": 1, "b": 1}, {"b": 1, "c": 1})
    assert 0.0 < v < 1.0
