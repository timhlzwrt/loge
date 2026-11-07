import Foundation
import LogeCore

/// A movie or episode whose sources should be listed.
struct SourcesRoute: Hashable, Identifiable {
    let item: WatchItem
    /// "Lanterns · S1 E2", shown as the screen and player title.
    let title: String
    /// Start playing straight away with the source last used for this title, if there is
    /// one, rather than waiting for a choice. The list stays underneath as a fallback.
    var autoplay = false
    /// The movie's or series' listed runtime in seconds, to estimate bitrates from file sizes.
    var runtime: TimeInterval?

    var type: String { item.type }
    var id: String { item.id }
}
