// FeedParser — streaming XML → ParsedFeed decoding. No SwiftData import.
// Field mapping source of truth: docs/spec/feed-field-mapping.md
import Foundation

/// Decodes an RSS/iTunes podcast feed body into a ``ParsedFeed``.
///
/// Uses `XMLParser` (event-driven / streaming) rather than a full DOM, per
/// the field-mapping doc's parsing-behavior note. Never traps: malformed
/// input surfaces as a typed ``FeedError``.
public enum FeedParser {
    /// Parses a feed body already in memory.
    ///
    /// - Parameters:
    ///   - data: the raw feed body (expected to be RSS 2.0 XML).
    ///   - feedURL: the URL the body was fetched from — becomes
    ///     `ParsedFeed.feedURL`, the identity used by the upsert layer.
    /// - Throws: `FeedError.malformedFeed` when the body isn't XML, has no
    ///   `<rss>`/`<channel>`, or the channel has no `<title>`.
    public static func parse(data: Data, feedURL: URL) throws -> ParsedFeed {
        let delegate = FeedParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        guard parser.parse() else {
            let reason = parser.parserError.map { "XML parse error: \($0.localizedDescription)" }
                ?? "Body could not be parsed as XML."
            throw FeedError.malformedFeed(reason: reason)
        }

        guard delegate.sawChannel else {
            throw FeedError.malformedFeed(reason: "Feed has no <rss>/<channel> element.")
        }

        guard let title = delegate.channelTitle, !title.isEmpty else {
            throw FeedError.malformedFeed(reason: "Channel is missing a required <title>.")
        }

        let author = firstNonEmpty(
            delegate.channelItunesAuthor,
            delegate.channelManagingEditor,
            delegate.channelOwnerName
        ) ?? ""

        let artworkURL = delegate.channelArtworkURLFromItunes ?? delegate.channelArtworkURLFromImage
        let category = firstNonEmpty(delegate.channelCategoryFromItunes, delegate.channelCategoryPlain) ?? ""
        let summary = firstNonEmpty(delegate.channelDescription, delegate.channelItunesSummary) ?? ""

        return ParsedFeed(
            feedURL: feedURL,
            title: title,
            author: author,
            homeURL: delegate.channelHomeURL,
            artworkURL: artworkURL,
            category: category,
            summary: summary,
            episodes: delegate.episodes
        )
    }

    fileprivate static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

/// `XMLParserDelegate` that accumulates channel- and item-level fields
/// while streaming through the document. One instance per parse.
private final class FeedParserDelegate: NSObject, XMLParserDelegate {
    private var elementStack: [String] = []
    private var textBuffer = ""

    private(set) var sawChannel = false
    private(set) var channelTitle: String?
    private(set) var channelItunesAuthor: String?
    private(set) var channelManagingEditor: String?
    private(set) var channelOwnerName: String?
    private(set) var channelHomeURL: URL?
    private(set) var channelArtworkURLFromItunes: URL?
    private(set) var channelArtworkURLFromImage: URL?
    private(set) var channelCategoryFromItunes: String?
    private(set) var channelCategoryPlain: String?
    private(set) var channelDescription: String?
    private(set) var channelItunesSummary: String?

    private(set) var episodes: [ParsedEpisode] = []

    // Per-item scratch state, reset on <item> start / finalize.
    private var currentGuid: String?
    private var currentEnclosureURL: URL?
    private var currentEnclosureIsAudio = false
    private var currentTitle: String?
    private var currentItunesTitle: String?
    private var currentDescription: String?
    private var currentItunesSummary: String?
    private var currentContentEncoded: String?
    private var currentPubDate: Date?
    private var currentDuration: TimeInterval?
    private var currentIsExplicit = false
    private var currentRemoteArtworkURL: URL?

    private var insideItem: Bool { elementStack.contains("item") }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        elementStack.append(elementName)
        textBuffer = ""

        switch elementName {
        case "channel":
            sawChannel = true

        case "item":
            resetItemScratchState()

        case "itunes:image":
            guard let href = attributeDict["href"], let url = URL(string: href) else { return }
            if insideItem {
                currentRemoteArtworkURL = url
            } else if channelArtworkURLFromItunes == nil {
                channelArtworkURLFromItunes = url
            }

        case "itunes:category":
            guard !insideItem, channelCategoryFromItunes == nil, let text = attributeDict["text"], !text.isEmpty else { return }
            channelCategoryFromItunes = text

        case "enclosure":
            guard insideItem else { return }
            if let urlString = attributeDict["url"], let url = URL(string: urlString) {
                currentEnclosureURL = url
            }
            if let type = attributeDict["type"], type.hasPrefix("audio/") {
                currentEnclosureIsAudio = true
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        textBuffer = ""
        let parent = elementStack.dropLast().last

        switch elementName {
        case "title":
            if insideItem {
                currentTitle = text
            } else {
                channelTitle = text
            }

        case "link":
            if !insideItem, channelHomeURL == nil, let url = URL(string: text) {
                channelHomeURL = url
            }

        case "itunes:author":
            if !insideItem, !text.isEmpty {
                channelItunesAuthor = text
            }

        case "managingEditor":
            if !insideItem, !text.isEmpty {
                channelManagingEditor = text
            }

        case "itunes:name":
            if !insideItem, parent == "itunes:owner", !text.isEmpty {
                channelOwnerName = text
            }

        case "url":
            if !insideItem, parent == "image", channelArtworkURLFromImage == nil, let url = URL(string: text) {
                channelArtworkURLFromImage = url
            }

        case "category":
            if !insideItem, channelCategoryPlain == nil, !text.isEmpty {
                channelCategoryPlain = text
            }

        case "guid":
            if insideItem, !text.isEmpty {
                currentGuid = text
            }

        case "itunes:title":
            if insideItem, !text.isEmpty {
                currentItunesTitle = text
            }

        case "description":
            if insideItem {
                if !text.isEmpty { currentDescription = text }
            } else if channelDescription == nil, !text.isEmpty {
                channelDescription = text
            }

        case "itunes:summary":
            if insideItem {
                if !text.isEmpty { currentItunesSummary = text }
            } else if channelItunesSummary == nil, !text.isEmpty {
                channelItunesSummary = text
            }

        case "content:encoded":
            if insideItem, !text.isEmpty {
                currentContentEncoded = text
            }

        case "pubDate":
            if insideItem, let date = Self.parseRFC822Date(text) {
                currentPubDate = date
            }

        case "itunes:duration":
            if insideItem, let duration = Self.parseDuration(text) {
                currentDuration = duration
            }

        case "itunes:explicit":
            if insideItem {
                currentIsExplicit = ["yes", "true"].contains(text.lowercased())
            }

        case "item":
            finalizeCurrentItem()

        default:
            break
        }

        elementStack.removeLast()
    }

    // MARK: - Item lifecycle

    private func resetItemScratchState() {
        currentGuid = nil
        currentEnclosureURL = nil
        currentEnclosureIsAudio = false
        currentTitle = nil
        currentItunesTitle = nil
        currentDescription = nil
        currentItunesSummary = nil
        currentContentEncoded = nil
        currentPubDate = nil
        currentDuration = nil
        currentIsExplicit = false
        currentRemoteArtworkURL = nil
    }

    /// Builds a `ParsedEpisode` from the current item scratch state and
    /// appends it, unless the item has no usable audio enclosure — in which
    /// case it is silently skipped (this single condition covers both the
    /// "missing guid + enclosure" and "missing audioURL" rows in the
    /// field-mapping doc, since `audioURL` is a required, non-optional field).
    private func finalizeCurrentItem() {
        defer { resetItemScratchState() }

        guard currentEnclosureIsAudio, let audioURL = currentEnclosureURL else {
            return
        }

        let guid: String
        if let currentGuid, !currentGuid.isEmpty {
            guid = currentGuid
        } else {
            guid = audioURL.absoluteString
        }
        let title = FeedParser.firstNonEmpty(currentTitle, currentItunesTitle) ?? "Untitled Episode"
        let summary = FeedParser.firstNonEmpty(currentDescription, currentItunesSummary, currentContentEncoded) ?? ""

        episodes.append(
            ParsedEpisode(
                guid: guid,
                title: title,
                summary: summary,
                publishDate: currentPubDate ?? .distantPast,
                duration: currentDuration ?? 0,
                audioURL: audioURL,
                remoteArtworkURL: currentRemoteArtworkURL,
                isExplicit: currentIsExplicit
            )
        )
    }

    // MARK: - Field decoding helpers

    /// Parses an RFC 822 `<pubDate>` value. Accepts both the numeric-offset
    /// (`+0000`) and named zone (`GMT`) forms feeds commonly use.
    fileprivate static func parseRFC822Date(_ value: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    /// Parses `<itunes:duration>`, accepting `SS`, `MM:SS`, `HH:MM:SS`, or a
    /// plain seconds value.
    fileprivate static func parseDuration(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ":").map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }

        switch parts.count {
        case 1:
            return TimeInterval(parts[0])
        case 2:
            guard let minutes = TimeInterval(parts[0]), let seconds = TimeInterval(parts[1]) else { return nil }
            return minutes * 60 + seconds
        case 3:
            guard let hours = TimeInterval(parts[0]), let minutes = TimeInterval(parts[1]), let seconds = TimeInterval(parts[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        default:
            return nil
        }
    }
}
