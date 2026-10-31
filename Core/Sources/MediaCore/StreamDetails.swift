import Foundation

/// What a stream's free text says about the file. Every addon formats its names and
/// descriptions differently, so this reads the release tags they share rather than any
/// one layout: "2160p", "DV", "x265", "Atmos", "58.2 GB" and so on.
public struct StreamDetails: Sendable, Equatable {
    public enum Resolution: Int, Sendable, Comparable {
        case sd = 480, hd = 720, fullHD = 1080, ultraHD = 2160

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        public var label: String {
            switch self {
            case .sd: "SD"
            case .hd: "720p"
            case .fullHD: "1080p"
            case .ultraHD: "4K"
            }
        }
    }

    public var resolution: Resolution?
    /// "Dolby Vision", "HDR10+", "HDR10" or "HLG", best first; a file can carry several.
    public var dynamicRange: [String] = []
    public var codec: String?
    /// The format, then the channel layout: "Atmos", "TrueHD", "7.1".
    public var audio: [String] = []
    public var source: String?
    public var size: Measurement<UnitInformationStorage>?
    /// Debrid services mark files they already hold; others have to be fetched first and
    /// often stall. Nil when the addon doesn't say.
    public var isCached: Bool?

    public init(_ stream: StreamSource) {
        let text = [stream.name, stream.title, stream.description, stream.behaviorHints?.filename]
            .compactMap { $0 }
            .joined(separator: "\n")
        self.init(text: text)
    }

    init(text: String) {
        // Simple word boundaries: release names separate tags with dots, which Unicode's
        // default rules treat as part of a word ("HDR10.HEVC").
        func has<Output>(_ pattern: Regex<Output>) -> Bool {
            text.contains(pattern.ignoresCase().wordBoundaryKind(.simple))
        }

        resolution = if has(/\b(2160p|4k|uhd)\b/) { .ultraHD }
            else if has(/\b1080[pi]\b/) { .fullHD }
            else if has(/\b720p\b/) { .hd }
            else if has(/\b(480p|576p|sd)\b/) { .sd }
            else { nil }

        if has(/\b(dv|dovi|dolby[ .]?vision)\b/) { dynamicRange.append("Dolby Vision") }
        if has(/\bhdr10(\+|plus)/) {
            dynamicRange.append("HDR10+")
        } else if has(/\bhdr(10)?\b/) {
            dynamicRange.append("HDR10")
        }
        if has(/\bhlg\b/) { dynamicRange.append("HLG") }

        codec = if has(/\b(hevc|[xh][ .]?265)\b/) { "HEVC" }
            else if has(/\bav1\b/) { "AV1" }
            else if has(/\b(avc|[xh][ .]?264)\b/) { "AVC" }
            else { nil }

        if has(/\batmos\b/) { audio.append("Atmos") }
        if has(/\btrue[ -]?hd\b/) {
            audio.append("TrueHD")
        } else if has(/\bdts[ -]?(hd|x|ma)\b/) {
            audio.append("DTS-HD")
        } else if has(/\bdts\b/) {
            audio.append("DTS")
        } else if has(/\b(ddp|dd\+|e-?ac-?3)/) {
            audio.append("Dolby Digital Plus")
        } else if has(/\b(dd|ac-?3)\b/) {
            audio.append("Dolby Digital")
        }
        // Written after the format ("DDP5.1"), and not to be confused with a size ("25.1 GB").
        if let channels = text.firstMatch(of: /(?:^|[^\d.,])([257])\.([01])(?!\d|\s*[GMT]i?B)/) {
            audio.append("\(channels.1).\(channels.2)")
        }

        source = if has(/\bremux\b/) { "Remux" }
            else if has(/\b(blu-?ray|bdrip|brrip)\b/) { "Blu-ray" }
            else if has(/\bweb[ .-]?dl\b/) { "WEB-DL" }
            else if has(/\bweb[ .-]?rip\b/) { "WEBRip" }
            else if has(/\bhdtv\b/) { "HDTV" }
            else { nil }

        if let match = text.firstMatch(of: /(\d+(?:[.,]\d+)?)\s*(TB|TiB|GB|GiB|MB|MiB)\b/.ignoresCase()),
           let value = Double(match.1.replacingOccurrences(of: ",", with: ".")) {
            let unit: UnitInformationStorage = switch match.2.uppercased() {
            case "TB", "TIB": .terabytes
            case "MB", "MIB": .megabytes
            default: .gigabytes
            }
            size = Measurement(value: value, unit: unit)
        }

        // "[RD+]" is Torrentio's and AIOStreams' mark for a cached file, "[RD download]"
        // or an hourglass for one that isn't; "⚡" is used for cached by several addons.
        if has(/\[[a-z]{2}\+\]|⚡|\bcached\b/) && !has(/\buncached\b/) {
            isCached = true
        } else if has(/\[[a-z]{2} download\]|⏳|\buncached\b/) {
            isCached = false
        }
    }

    /// "4K · Dolby Vision · HEVC": what decides how the picture looks.
    public var picture: String? {
        let parts = [resolution?.label] + dynamicRange.map(Optional.some) + [codec]
        let kept = parts.compactMap { $0 }
        return kept.isEmpty ? nil : kept.joined(separator: " · ")
    }

    /// "Remux · Atmos 7.1 · 58.2 GB": the rest of what tells two files apart.
    public var file: String? {
        let audio = audio.isEmpty ? nil : audio.joined(separator: " ")
        let size = size.map { $0.formatted(.byteCount(style: .file)) }
        let kept = [source, audio, size].compactMap { $0 }
        return kept.isEmpty ? nil : kept.joined(separator: " · ")
    }

    /// Best first: higher resolution, then files the debrid service already holds, then
    /// larger files, which at the same resolution usually means a better encode.
    public static func bestFirst(_ lhs: StreamDetails, _ rhs: StreamDetails) -> Bool {
        if lhs.resolution != rhs.resolution {
            return (lhs.resolution?.rawValue ?? 0) > (rhs.resolution?.rawValue ?? 0)
        }
        if lhs.isCached != rhs.isCached {
            return lhs.isCached == true || rhs.isCached == false
        }
        return (lhs.size?.converted(to: .bytes).value ?? 0) > (rhs.size?.converted(to: .bytes).value ?? 0)
    }
}
