// CarPlay template assembly. Architecture source: docs/design/carplay-ia.md (v1)
// — a template-driven, glance-and-go experience (Up Next / Podcasts / Downloads
// tabs + a now-playing surface). This is the M1 dormant seam: it builds the full
// template tree but depends on NO playback logic (PlaybackKit arrives at M3).
// Real data and transport are injected through the provider/handler protocols
// below so M3 can light this up without touching the factory.
#if canImport(CarPlay)
import CarPlay
import UIKit
import Foundation
import PodcastModels

// MARK: - Injection seams

/// Supplies the model rows CarPlay renders. CarPlay adds no business logic of
/// its own (per the IA doc §Notes) — every list is sourced from the same
/// `PodcastModels` store the phone app uses. M3 registers a concrete provider
/// backed by the shared engine; until then `EmptyCarPlayContentProvider` keeps
/// the seam inert.
@MainActor
public protocol CarPlayContentProviding: AnyObject {
    /// The current or most-recently-played episode for the "Now / Continue"
    /// section, or `nil` when nothing has been started.
    func nowOrContinueEpisode() -> Episode?
    /// The ordered "Up Next" queue (ascending = plays sooner).
    func upNextEpisodes() -> [Episode]
    /// Subscribed shows for the Podcasts tab (Level 1).
    func subscribedPodcasts() -> [Podcast]
    /// Episodes for a selected show (Podcasts Level 2), newest first.
    func episodes(for podcast: Podcast) -> [Episode]
    /// Episodes with a complete local copy, for the Downloads tab.
    func downloadedEpisodes() -> [Episode]
}

/// Receives transport intents from CarPlay rows and now-playing buttons. Left
/// unimplemented at M1; PlaybackKit conforms an adapter to it at M3.
@MainActor
public protocol CarPlayPlaybackHandling: AnyObject {
    /// Begin (or resume) playback of `episode`.
    func play(_ episode: Episode)
    /// Skip the playhead by `seconds` (negative = backwards).
    func skip(by seconds: TimeInterval)
    /// Seek the playhead to an absolute `time` offset in seconds.
    func seek(to time: TimeInterval)
}

/// A no-op provider that returns empty content. Used while the CarPlay seam is
/// dormant so the template tree renders (empty-state rows) without a store.
@MainActor
public final class EmptyCarPlayContentProvider: CarPlayContentProviding {
    public init() {}
    public func nowOrContinueEpisode() -> Episode? { nil }
    public func upNextEpisodes() -> [Episode] { [] }
    public func subscribedPodcasts() -> [Podcast] { [] }
    public func episodes(for podcast: Podcast) -> [Episode] { [] }
    public func downloadedEpisodes() -> [Episode] { [] }
}

/// Process-wide registration point for the CarPlay data/transport seam. M3 sets
/// these once during app start (from a scene that owns the shared engine); the
/// scene delegate falls back to `EmptyCarPlayContentProvider` when unset.
public enum CarPlayIntegration {
    /// The provider the scene delegate uses when a CarPlay scene connects.
    @MainActor public static var contentProvider: (any CarPlayContentProviding)?
    /// The transport handler the factory forwards row/button taps to.
    @MainActor public static var playbackHandler: (any CarPlayPlaybackHandling)?
}

// MARK: - Factory

/// Builds the CarPlay template tree from `PodcastModels` content. Holds a weak
/// reference to the live `CPInterfaceController` (set by the scene delegate) so
/// row taps can push detail / now-playing templates.
@MainActor
public final class CarPlayTemplateFactory {

    private let content: any CarPlayContentProviding
    private var playback: (any CarPlayPlaybackHandling)? {
        CarPlayIntegration.playbackHandler
    }

    /// The active interface controller. Assigned by the scene delegate on
    /// connect; used to push Level-2, chapter, and now-playing templates.
    public weak var interfaceController: CPInterfaceController?

    public init(content: any CarPlayContentProviding = EmptyCarPlayContentProvider()) {
        self.content = content
    }

    // MARK: Root

    /// Assembles the root `CPTabBarTemplate`. Tab order matches the IA: Up Next
    /// (default selected, first), Podcasts, Downloads. Discover/Search is
    /// intentionally absent on CarPlay.
    public func makeRootTemplate() -> CPTabBarTemplate {
        let tabs: [CPListTemplate] = [
            makeUpNextTab(),
            makePodcastsTab(),
            makeDownloadsTab()
        ]
        return CPTabBarTemplate(templates: tabs)
    }

    // MARK: Up Next tab

    private func makeUpNextTab() -> CPListTemplate {
        var sections: [CPListSection] = []

        if let current = content.nowOrContinueEpisode() {
            let row = makePlayRow(for: current, detail: upNextDetail(for: current))
            sections.append(CPListSection(items: [row], header: "Now / Continue", sectionIndexTitle: nil))
        }

        let queue = content.upNextEpisodes()
        if queue.isEmpty {
            sections.append(
                CPListSection(
                    items: [placeholderRow("Your queue is empty — add episodes from your phone.")],
                    header: "Up Next",
                    sectionIndexTitle: nil
                )
            )
        } else {
            let rows = queue.map { makePlayRow(for: $0, detail: upNextDetail(for: $0)) }
            sections.append(CPListSection(items: rows, header: "Up Next", sectionIndexTitle: nil))
        }

        let template = CPListTemplate(title: "Up Next", sections: sections)
        template.tabTitle = "Up Next"
        template.tabImage = UIImage(systemName: "list.bullet")
        return template
    }

    // MARK: Podcasts tab (two levels)

    private func makePodcastsTab() -> CPListTemplate {
        let shows = content.subscribedPodcasts()
        let items: [CPListItem]
        if shows.isEmpty {
            items = [placeholderRow("No subscriptions yet — subscribe on your phone.")]
        } else {
            items = shows.map { show in
                let item = CPListItem(
                    text: show.title,
                    detailText: podcastDetail(for: show),
                    image: nil,
                    accessoryImage: nil,
                    accessoryType: .disclosureIndicator
                )
                item.handler = { [weak self] _, completion in
                    self?.pushEpisodeList(for: show)
                    completion()
                }
                return item
            }
        }

        let template = CPListTemplate(title: "Podcasts", sections: [CPListSection(items: items)])
        template.tabTitle = "Podcasts"
        template.tabImage = UIImage(systemName: "square.stack")
        return template
    }

    private func pushEpisodeList(for podcast: Podcast) {
        let episodes = content.episodes(for: podcast)
        let items: [CPListItem]
        if episodes.isEmpty {
            items = [placeholderRow("No episodes available.")]
        } else {
            items = episodes.map { makePlayRow(for: $0, detail: episodeDetail(for: $0)) }
        }
        let template = CPListTemplate(title: podcast.title, sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: Downloads tab

    private func makeDownloadsTab() -> CPListTemplate {
        let downloads = content.downloadedEpisodes()
        let items: [CPListItem]
        if downloads.isEmpty {
            items = [placeholderRow("No downloads yet.")]
        } else {
            items = downloads.map { episode in
                let row = makePlayRow(for: episode, detail: downloadDetail(for: episode))
                row.accessoryType = .cloud
                return row
            }
        }

        let template = CPListTemplate(
            title: "Downloads",
            sections: [CPListSection(items: items, header: "Downloaded", sectionIndexTitle: nil)]
        )
        template.tabTitle = "Downloads"
        template.tabImage = UIImage(systemName: "arrow.down.circle")
        return template
    }

    // MARK: Now Playing

    /// Configures and returns the shared `CPNowPlayingTemplate` for the current
    /// episode. Apple renders artwork/scrubber/title; we supply the custom
    /// button set from the IA: 30s skip back/forward, a chapters button (only
    /// when the episode has chapters), and the system Up Next button.
    @discardableResult
    public func makeNowPlaying() -> CPNowPlayingTemplate {
        configureNowPlaying(for: content.nowOrContinueEpisode())
    }

    @discardableResult
    private func configureNowPlaying(for episode: Episode?) -> CPNowPlayingTemplate {
        let template = CPNowPlayingTemplate.shared

        // Distances mirror PlaybackKit.SkipInterval (back 15 / forward 30), kept
        // as literals here because this factory is intentionally decoupled from
        // PlaybackKit (it drives the CarPlayPlaybackHandling seam, not the engine).
        // Previously CarPlay rewound 30s while every other surface rewound 15s;
        // corrected to 15 for consistency.
        let skipBack = CPNowPlayingImageButton(image: skipImage(named: "gobackward.15")) { [weak self] _ in
            self?.playback?.skip(by: -15)
        }
        let skipForward = CPNowPlayingImageButton(image: skipImage(named: "goforward.30")) { [weak self] _ in
            self?.playback?.skip(by: 30)
        }

        var buttons: [CPNowPlayingButton] = [skipBack, skipForward]

        // Chapters button: shown ONLY when the episode has chapters (hide, not
        // disable, per IA §6). Tap pushes a chapter-marker list that seeks.
        if let episode, !episode.chapters.isEmpty {
            let chaptersButton = CPNowPlayingImageButton(image: skipImage(named: "list.bullet.rectangle")) { [weak self] _ in
                self?.pushChapters(for: episode)
            }
            buttons.append(chaptersButton)
        }

        template.updateNowPlayingButtons(buttons)
        // Surface the system Up Next list, backed by our queue.
        template.isUpNextButtonEnabled = true
        template.isAlbumArtistButtonEnabled = false
        return template
    }

    private func pushChapters(for episode: Episode) {
        let markers = episode.chapters.sorted { $0.startTime < $1.startTime }
        let items = markers.map { chapter -> CPListItem in
            let item = CPListItem(text: chapter.title, detailText: Self.timeString(chapter.startTime))
            item.handler = { [weak self] _, completion in
                self?.playback?.seek(to: chapter.startTime)
                completion()
            }
            return item
        }
        let template = CPListTemplate(title: "Chapters", sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: Row builders

    /// A tappable episode row: tap starts playback and pushes now-playing.
    private func makePlayRow(for episode: Episode, detail: String) -> CPListItem {
        let item = CPListItem(text: episode.title, detailText: detail)
        item.playbackProgress = CGFloat(episode.playbackProgress)
        item.isExplicitContent = episode.isExplicit
        item.handler = { [weak self] _, completion in
            self?.play(episode)
            completion()
        }
        return item
    }

    /// A non-actionable placeholder row for empty states.
    private func placeholderRow(_ text: String) -> CPListItem {
        CPListItem(text: text, detailText: nil)
    }

    private func play(_ episode: Episode) {
        playback?.play(episode)
        let template = configureNowPlaying(for: episode)
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: Detail-text formatting

    private func upNextDetail(for episode: Episode) -> String {
        let show = episode.podcast?.title ?? "Podcast"
        let mins = max(Int((episode.remainingTime / 60).rounded()), 0)
        return "\(show) · \(mins) min left"
    }

    private func podcastDetail(for podcast: Podcast) -> String {
        let unplayed = podcast.episodes.filter { !$0.isPlayed }.count
        let author = podcast.author.isEmpty ? "Unknown" : podcast.author
        return "\(author) · \(unplayed) new"
    }

    private func episodeDetail(for episode: Episode) -> String {
        "\(Self.dateString(episode.publishDate)) · \(Self.durationString(episode.duration))"
    }

    private func downloadDetail(for episode: Episode) -> String {
        let show = episode.podcast?.title ?? "Podcast"
        return "\(show) · \(Self.durationString(episode.duration))"
    }

    // MARK: Image + formatter helpers

    private func skipImage(named symbol: String) -> UIImage {
        UIImage(systemName: symbol) ?? UIImage()
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    private static func dateString(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// "42 min" (or "1 h 5 min" for long items); "—" when unknown.
    private static func durationString(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let totalMinutes = Int((seconds / 60).rounded())
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    /// "mm:ss" or "h:mm:ss" chapter start time.
    private static func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
#endif
