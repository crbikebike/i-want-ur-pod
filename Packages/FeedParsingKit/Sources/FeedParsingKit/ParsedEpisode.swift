// ParsedEpisode — pure value DTO for one feed <item>. No SwiftData import.
// Field mapping source of truth: docs/spec/feed-field-mapping.md
import Foundation

/// A single feed item, decoded but not yet persisted.
///
/// Foundation-pure and `Sendable` so it can cross actor/concurrency
/// boundaries between the fetch/parse layer and the (separate) SwiftData
/// upsert layer.
public struct ParsedEpisode: Sendable, Hashable {
    /// `<guid>`, falling back to the enclosure URL. Never empty — items
    /// missing both are skipped before construction.
    public var guid: String

    /// `<title>` → `<itunes:title>` → `"Untitled Episode"`.
    public var title: String

    /// `<description>` → `<itunes:summary>` → `<content:encoded>` → `""`.
    public var summary: String

    /// `<pubDate>` (RFC 822) → `Date.distantPast`.
    public var publishDate: Date

    /// `<itunes:duration>` in seconds → `0`.
    public var duration: TimeInterval

    /// `<enclosure url>` where `type` is `audio/*`. Never absent — items
    /// missing a usable audio enclosure are skipped before construction.
    public var audioURL: URL

    /// `<itunes:image href>` → `nil`.
    public var remoteArtworkURL: URL?

    /// `<itunes:explicit>` == yes/true → `false`.
    public var isExplicit: Bool

    public init(
        guid: String,
        title: String,
        summary: String = "",
        publishDate: Date = .distantPast,
        duration: TimeInterval = 0,
        audioURL: URL,
        remoteArtworkURL: URL? = nil,
        isExplicit: Bool = false
    ) {
        self.guid = guid
        self.title = title
        self.summary = summary
        self.publishDate = publishDate
        self.duration = duration
        self.audioURL = audioURL
        self.remoteArtworkURL = remoteArtworkURL
        self.isExplicit = isExplicit
    }
}
