"""The episode matcher: guid is identity, title is fallback, wrong is worse than none."""

from admin.api.apple import pick_episode, _norm


def test_guid_wins_over_a_matching_title():
    entries = [{"episodeGuid": "g2", "trackName": "Chapter 1", "trackViewUrl": "wrong"},
               {"episodeGuid": "g1", "trackName": "Renamed on Apple", "trackViewUrl": "right"}]
    assert pick_episode(entries, "Chapter 1", "g1")["trackViewUrl"] == "right"


def test_title_fallback_is_exact_and_case_blind():
    entries = [{"episodeGuid": "x", "trackName": "The Widow and the Winchester"}]
    assert pick_episode(entries, "the widow AND the winchester", "no-such-guid")
    assert pick_episode(entries, "The Widow", "no-such-guid") is None


def test_no_match_is_none_not_a_guess():
    assert pick_episode([{"trackName": "Other"}], "Chapter 1", None) is None


def test_feed_urls_agree_across_scheme_www_and_trailing_slash():
    assert _norm("http://www.feeds.example.com/rss/") == _norm("https://feeds.example.com/rss")
