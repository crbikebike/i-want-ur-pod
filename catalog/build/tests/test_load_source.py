"""Tests for the loader's judgment calls.

Two decisions here can quietly lose or mislabel a show, so they get pinned down:
which member of a duplicate pair to flag, and what language a show is in.
"""

import pytest

from catalog.build import load_source as ls


# --- picking which duplicate to flag -------------------------------------------


def test_prefixed_child_is_flagged_and_parent_is_not():
    suspects = ls._pick_suspects([["slow-burn", "slow-burn-biggie-tupac"]], [])
    assert "slow-burn-biggie-tupac" in suspects
    assert "slow-burn" not in suspects


def test_both_are_flagged_when_neither_is_the_parent():
    """Making Obama and Making Oprah share a WBEZ feed but neither contains the other."""
    suspects = ls._pick_suspects([["making-obama", "making-oprah"]], [])
    assert set(suspects) == {"making-obama", "making-oprah"}


def test_flagging_all_members_keeps_the_partial_unique_index_satisfiable():
    """At most one show per feed may be left unflagged, whatever the group shape."""
    for group in (
        ["a", "a-child", "a-other"],
        ["x", "y"],
        ["p", "p-one", "q"],
    ):
        suspects = ls._pick_suspects([group], [])
        assert len([s for s in group if s not in suspects]) <= 1, group


def test_a_parent_with_several_children_stays_unflagged():
    suspects = ls._pick_suspects([["serial", "serial-s2", "serial-s3"]], [])
    assert "serial" not in suspects
    assert {"serial-s2", "serial-s3"} <= set(suspects)


def test_content_overlap_flags_the_child_on_a_separate_feed():
    suspects = ls._pick_suspects([], [("turning", "turning-the-sisters-who-left", 10)])
    assert "turning-the-sisters-who-left" in suspects
    assert "turning" not in suspects


def test_content_overlap_with_no_prefix_flags_both():
    suspects = ls._pick_suspects([], [("ear-hustle", "loop", 6)])
    assert set(suspects) == {"ear-hustle", "loop"}


def test_a_shared_feed_verdict_is_not_overwritten_by_content_overlap():
    """The feed_url signal is authoritative; it must not be downgraded by the weaker one."""
    suspects = ls._pick_suspects(
        [["slow-burn", "slow-burn-biggie-tupac"]],
        [("slow-burn", "slow-burn-biggie-tupac", 205)],
    )
    assert "slow-burn" not in suspects
    assert "shares its feed" in suspects["slow-burn-biggie-tupac"]


# --- language detection ---------------------------------------------------------

SPANISH = [
    "El caso que nadie quiso investigar",
    "Los archivos del silencio, para siempre",
    "Una historia con final abierto",
    "Como se perdio el expediente del juez",
    "Por que las familias siguen buscando mas",
]
FRENCH = [
    "Le dossier qui a tout change",
    "Les archives des annees noires",
    "Une enquete pour comprendre",
    "Ce qui est arrive dans la nuit",
    "Sur les traces des disparus aux frontieres",
]
ENGLISH = [
    "The Case Nobody Wanted to Investigate",
    "Archives of Silence, Part One",
    "A Story With No Ending",
    "How the Judge's File Went Missing",
    "Why the Families Are Still Searching",
]


def test_spanish_titles_are_detected():
    lang, evidence = ls._detect_language(SPANISH)
    assert lang == "es"
    assert evidence


def test_french_titles_are_detected():
    assert ls._detect_language(FRENCH)[0] == "fr"


def test_english_titles_stay_english():
    assert ls._detect_language(ENGLISH)[0] == "en"


def test_a_show_with_too_few_titles_is_not_guessed_at():
    assert ls._detect_language(SPANISH[:2]) == ("en", "")


def test_one_repeated_marker_cannot_carry_a_verdict():
    """The failure mode of a rate-only threshold: 'as' alone once read Hollywoodland
    as Portuguese."""
    titles = [f"As Told By Number {i} As It Happened As Ever" for i in range(20)]
    assert ls._detect_language(titles)[0] == "en"


def test_titles_split_on_the_segment_separator():
    """Titles use '|' as a separator; without splitting it, the adjacent words merge
    and their markers stop matching."""
    titled = [
        f"Serie {i} | El caso de los archivos | Una parte mas para el juez que vino con las cintas del sur"
        for i in range(8)
    ]
    assert ls._detect_language(titled)[0] == "es"


@pytest.mark.parametrize("titles", [[], [""] * 10])
def test_empty_titles_do_not_crash(titles):
    assert ls._detect_language(titles)[0] == "en"
