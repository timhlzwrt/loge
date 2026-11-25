import LogeCore
import SwiftUI

/// A resolution's heading and its rows: on a rounded panel on the Mac, and on tvOS as a
/// section whose rows are focus targets of their own. iPhone and iPad list every row in one.
struct SourceGroupView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        #if os(tvOS)
        Section {
            content
        } header: {
            // Not `.secondary`: a list header dims its text again, which left these unreadable.
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                // Room for the first row, which grows into the header when focused.
                .padding(.bottom, 12)
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { index in
                        if index > 0 {
                            Divider().padding(.leading, 16)
                        }
                        rows[index]
                    }
                }
            }
            .background(.white.opacity(0.07), in: .rect(cornerRadius: Self.radius))
            .clipShape(.rect(cornerRadius: Self.radius))
        }
        #endif
    }

    #if os(macOS)
    private static var radius: CGFloat { 12 }
    #else
    private static var radius: CGFloat { 20 }
    #endif
}

/// One source: the release type with its best dynamic range, then codec and audio, with
/// the size on the right and the bitrate under it. Files the debrid service doesn't hold
/// yet are dimmed, since they usually stall.
struct StreamRow: View {
    let entry: ListedSource
    let isLastPlayed: Bool
    /// Set on the source recommended for this speed, in bits per second.
    let connectionSpeed: Double?

    var body: some View {
        #if os(iOS)
        phoneRow
        #else
        row
        #endif
    }

    #if os(iOS)
    /// The resolution in a small outlined box, what the file is, how it plays, and its size.
    private var phoneRow: some View {
        let details = entry.details
        let isCold = details.isCached == false
        return HStack(spacing: 12) {
            Text(details.resolution.map { $0 == .ultraHD || $0 == .sd ? $0.label : "\($0.rawValue)" } ?? "")
                .font(.footnote.weight(.bold))
                .frame(width: 46, height: 26)
                .overlay {
                    if details.resolution != nil {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.35), lineWidth: 1.5)
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
                    .foregroundStyle(.white.opacity(0.8))
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
    #else
    @ViewBuilder
    private var row: some View {
        let details = entry.details
        let isCold = details.isCached == false
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(titleFont)
                        .lineLimit(1)
                    // HDR is what tells two otherwise equal 4K files apart, so it sits by the
                    // title and is the last thing to be cut.
                    if let range = details.dynamicRange.first {
                        Text(range)
                            .font(summaryFont.weight(.semibold))
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                // The dynamic range is already beside the title.
                if let summary = details.summary(includingDynamicRange: false) {
                    Text(summary)
                        .font(summaryFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let note {
                    Text(note)
                        .font(summaryFont.weight(.medium))
                        .foregroundStyle(isLastPlayed || connectionSpeed != nil ? Self.highlight : AnyShapeStyle(.secondary))
                }
            }
            Spacer(minLength: 8)
            if details.bitrateLabel != nil || details.sizeLabel != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    if let size = details.sizeLabel {
                        Text(size)
                            .font(sizeFont.weight(.semibold).monospacedDigit())
                    }
                    if let bitrate = details.bitrateLabel {
                        Text(bitrate)
                            .font(summaryFont.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(details.bitrate == nil ? "about \(bitrate.dropFirst())" : bitrate)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .opacity(isCold ? 0.55 : 1)
        #if !os(tvOS)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: rowHeight)
        #endif
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
    #endif

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
    private let titleFont = Font.headline
    private let summaryFont = Font.caption
    private let sizeFont = Font.callout
    #elseif os(macOS)
    private let titleFont = Font.body.weight(.semibold)
    private let summaryFont = Font.subheadline
    private let sizeFont = Font.body
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
