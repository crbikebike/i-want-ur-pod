"""The tally is where escalation could quietly lie. Pin its arithmetic."""

from admin.api.escalate import decide


def test_unanimous_three_is_high():
    got = decide("heist-and-robbery", ["heist-and-robbery"] * 3)
    assert got == {"winner": "heist-and-robbery", "agreement": 3, "votes": 3,
                   "confidence": "high", "demoted": None}


def test_two_against_one_replaces_the_primary_and_demotes_it():
    got = decide("organised-crime", ["heist-and-robbery", "heist-and-robbery",
                                     "organised-crime"])
    assert got["winner"] == "heist-and-robbery"
    assert got["agreement"] == 2
    assert got["confidence"] == "medium"
    assert got["demoted"] == "organised-crime"


def test_a_three_way_split_keeps_the_incumbent_at_low():
    got = decide("b-subject", ["a-subject", "b-subject", "c-subject"])
    assert got["winner"] == "b-subject"
    assert got["agreement"] == 1
    assert got["confidence"] == "low"
    assert got["demoted"] is None


def test_a_split_without_the_incumbent_falls_to_lexicographic_and_demotes():
    got = decide("original", ["zeta", "alpha", "mid"])
    assert got["winner"] == "alpha"
    assert got["demoted"] == "original"
    assert got["confidence"] == "low"


def test_a_tie_between_two_challengers_keeps_the_incumbent_if_it_is_one_of_them():
    got = decide("beta", ["alpha", "alpha", "beta", "beta"])
    assert got["winner"] == "beta"
    assert got["agreement"] == 2


def test_no_votes_is_none_not_a_crash():
    assert decide("anything", []) is None
