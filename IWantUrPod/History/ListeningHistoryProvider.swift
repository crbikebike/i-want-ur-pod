// Composed from docs/design/direction.md tokens — no design/kit source of its
// own (this is the testable data seam behind
// design/kit/screens/listening-history.html; see `ListeningHistoryScreen.swift`
// for the screen itself). Mirrors `HomeFeedProvider.swift` /
// `PodcastsListProvider.swift`'s precedent: grouping/derivation logic factored
// out of the screen so it can be exercised directly. Screens fetch the full
// `[PlayEvent]` set via `@Query(sort:order:)` (sort-only — never a
// `#Predicate` that groups/filters) and hand it to the pure functions below.
import Foundation
import PodcastModels

@MainActor
public enum ListeningHistoryProvider {

    // MARK: - Day grouping (.lh-daygroup / .lh-daylabel)

    /// One day-header group of `PlayEvent`s, in the order the log renders
    /// them (reverse-chronological within the group, groups newest-first).
    public struct DaySection: Identifiable, Sendable {
        public let id: Int
        public let label: String
        public let events: [PlayEvent]
    }

    /// Buckets `events` (already reverse-chronological, per the `@Query`
    /// sort) into day-header groups matching `listening-history.html`'s
    /// "Today" / "Yesterday" / "3 days ago" / "Last week" headers. Preserves
    /// each event's existing order within its bucket, and orders buckets by
    /// the order their first (newest) event appears — i.e. newest group first.
    public static func groupedByDay(_ events: [PlayEvent], now: Date = .now) -> [DaySection] {
        var order: [Int] = []
        var buckets: [Int: [PlayEvent]] = [:]

        for event in events {
            let key = bucketKey(for: event.playedAt, now: now)
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]!.append(event)
        }

        return order.map { key in
            DaySection(id: key, label: dayHeaderLabel(forBucketKey: key), events: buckets[key] ?? [])
        }
    }

    /// "Today" / "Yesterday" / "3 days ago" / "Last week" — the day-group
    /// header copy (distinct from `HomeFeedProvider.relativeDayLabel`'s
    /// terser per-row "3d ago", which the row's own trailing "when" label
    /// reuses instead). Beyond the kit's shown range (0–7 days) this
    /// extrapolates in the same spirit: "N weeks ago" for older groups,
    /// since the kit doesn't specify anything past "Last week".
    public static func dayHeaderLabel(for date: Date, now: Date = .now) -> String {
        dayHeaderLabel(forBucketKey: bucketKey(for: date, now: now))
    }

    /// Days between `date`'s calendar day and `now`'s, clamped so a
    /// future-dated event (clock skew) reads as "Today" rather than negative.
    private static func daysAgo(_ date: Date, now: Date) -> Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfThat = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfThat, to: startOfToday).day ?? 0
        return max(0, days)
    }

    /// A grouping key: one bucket per day for the first week (0...6), then
    /// one bucket per week after that — so every event in "Last week" (days
    /// 7–13) shares a single group, matching the header label's granularity.
    private static func bucketKey(for date: Date, now: Date) -> Int {
        let days = daysAgo(date, now: now)
        // Days 0–6 get their own bucket (0...6); days 7–13 all share bucket
        // 7 ("Last week"), days 14–20 share bucket 8 ("2 weeks ago"), etc.
        return days < 7 ? days : 6 + (days / 7)
    }

    private static func dayHeaderLabel(forBucketKey key: Int) -> String {
        switch key {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(key) days ago"
        case 7: return "Last week"
        default:
            let weeks = key - 6
            return "\(weeks) weeks ago"
        }
    }

    // MARK: - Per-episode play count (.lh-playcount "Played N×")

    /// The de-duplication key an episode is counted under: its feed GUID
    /// when known, else its title — matching the build brief's "group by
    /// `episodeGUID`, fallback `episodeTitle`".
    public static func playCountKey(for event: PlayEvent) -> String {
        event.episodeGUID ?? event.episodeTitle
    }

    /// How many logged sessions exist for the same episode as `event`,
    /// across the full history (not just its day group) — an episode played
    /// once today and twice three days ago is "Played 3×" in both places.
    public static func playCounts(for events: [PlayEvent]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for event in events {
            counts[playCountKey(for: event), default: 0] += 1
        }
        return counts
    }

    // MARK: - Listened-duration label (.lh-dur "24 min listened")

    /// "24 min listened" under an hour, "1h 12m listened" at/over an hour —
    /// matches `listening-history.html`'s `.lh-dur` copy exactly. Mirrors
    /// `HomeFeedProvider.durationLabel`'s "round to the nearest minute"
    /// idiom, extended with an hours component the kit's row needs but
    /// `durationLabel` never did.
    public static func listenedDurationLabel(forSeconds seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        guard totalMinutes >= 60 else {
            return "\(totalMinutes) min listened"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m listened"
    }
}
