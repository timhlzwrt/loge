import LogeCore
import SwiftUI

/// One source: the release type with its best dynamic range, then codec and audio, with
/// the size on the right and the bitrate under it. Files the debrid service doesn't hold
/// yet are dimmed, since they usually stall.
struct StreamRow: View {
    let entry: ListedSource
    let isLastPlayed: Bool
    /// Set on the source recommended for this speed, in bits per second.
    let connectionSpeed: Double?

    /// The resolution in a small outlined box, what the file is, how it plays, and its size.
    /// Colours are relative to the row's, so a focused white row on Apple TV turns them dark.
    var body: some View {
        let details = entry.details
        let isCold = details.isCached == false
        return HStack(spacing: 12) {
            Text(details.resolution.map { $0 == .ultraHD || $0 == .sd ? $0.label : "\($0.rawValue)" } ?? "")
                .font(.footnote.weight(.bold))
                .frame(width: 46, height: 26)
                .overlay {
                    if details.resolution != nil {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(.tertiary, lineWidth: 1.5)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text([title, details.dynamicRange.first].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let detail = isCold ? "Not cached, starts slowly" : playDetail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if isLastPlayed || connectionSpeed != nil, let note {
                    Text(note)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Self.highlight)
                }
            }
            Spacer(minLength: 8)
            if let size = details.sizeLabel {
                Text(size)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize()
            }
        }
        .opacity(isCold ? 0.5 : 1)
        .padding(.vertical, 12)
        .frame(minHeight: rowHeight)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// "35 Mbps · HEVC · DD+ 5.1 · cached".
    private var playDetail: String? {
        let details = entry.details
        let parts = [details.bitrateLabel, details.codec, details.audio.isEmpty ? nil : details.audio.joined(separator: " "),
                     details.isCached == true ? "cached" : nil]
        return parts.compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    /// "Recommended for your 32 Mbps connection", "Last played", or a warning that the file
    /// isn't cached; shortened when it's both, to stay on one line. The warning stays on the
    /// other two, since dimming alone doesn't reach VoiceOver.
    private var note: String? {
        let isCold = entry.details.isCached == false
        let marked: String? = if isLastPlayed {
            connectionSpeed == nil ? "Last played" : "Last played · recommended"
        } else if let connectionSpeed {
            "Recommended for your "
                + "\((connectionSpeed / 1_000_000).formatted(.number.precision(.fractionLength(0)).locale(.interface))) Mbps connection"
        } else {
            nil
        }
        guard let marked else { return isCold ? "Not cached, may be slow to start" : nil }
        return isCold ? marked + " · not cached" : marked
    }

    /// The release type, the resolution when that's all an addon says, or the addon's own
    /// name line for streams none of the tags fit.
    private var title: String {
        let details = entry.details
        return details.releaseType ?? (details.summary() != nil ? details.resolution?.label : nil)
            ?? entry.stream.cleanName?.components(separatedBy: .newlines).joined(separator: " ")
            ?? "Source"
    }

    #if os(tvOS)
    /// Not the accent: the focused row is a platter in that colour, and the note vanished on it.
    private static let highlight = AnyShapeStyle(.primary)
    #else
    private static let highlight = AnyShapeStyle(.tint)
    #endif

    #if os(tvOS)
    private let rowHeight: CGFloat = 66
    #elseif os(macOS)
    /// A minimum only: rows with nothing under the title stay one line tall.
    private let rowHeight: CGFloat = 32
    #else
    /// The touch target; rows with nothing under the title stay one line tall.
    private let rowHeight: CGFloat = 44
    #endif
}

/// Stacks the groups on a phone or Mac; on tvOS they are already inside a `List`.
struct ListContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(tvOS)
        content
        #else
        VStack(alignment: .leading, spacing: 24) { content }
        #endif
    }
}
