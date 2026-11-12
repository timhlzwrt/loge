import LogeCore
import SwiftUI

/// A resolution's heading and its rows, on a rounded panel except on tvOS, where the
/// rows are focus targets of their own.
struct SourceGroupView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        #if os(tvOS)
        Section {
            content
        } header: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
                if let summary = summary(details) {
                    Text(summary)
                        .font(summaryFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let note {
                    Text(note)
                        .font(summaryFont.weight(.medium))
                        .foregroundStyle(isLastPlayed || connectionSpeed != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
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

    /// Codec and audio; the dynamic range is already beside the title.
    private func summary(_ details: StreamDetails) -> String? {
        let audio = details.audio.isEmpty ? nil : details.audio.joined(separator: " ")
        return [details.codec, audio].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    /// The release type, the resolution when that's all an addon says, or the addon's own
    /// name line for streams none of the tags fit.
    private var title: String {
        let details = entry.details
        return details.releaseType ?? (details.summary != nil ? details.resolution?.label : nil)
            ?? entry.stream.cleanName?.components(separatedBy: .newlines).joined(separator: " ")
            ?? "Source"
    }

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
    private let titleFont = Font.callout.weight(.semibold)
    private let summaryFont = Font.footnote
    private let sizeFont = Font.subheadline
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

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
