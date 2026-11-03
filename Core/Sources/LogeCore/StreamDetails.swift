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

    public enum SortOrder: String, CaseIterable, Identifiable, Sendable {
        case cachedFirst = "Cached first"
        case lowerBitrate = "Lower bitrate"
        case higherBitrate = "Higher bitrate"
        case smallerFile = "Smaller file"
        case addonOrder = "Addon order"

        public var id: Self { self }

        /// Equal or missing values leave the addon's own ranking intact.
        public func precedes(_ lhs: StreamDetails, _ rhs: StreamDetails) -> Bool {
            switch self {
            case .cachedFirst:
                func rank(_ cached: Bool?) -> Int { cached == true ? 0 : cached == nil ? 1 : 2 }
                return rank(lhs.isCached) < rank(rhs.isCached)
            case .lowerBitrate:
                return (lhs.listedBitrate ?? .infinity) < (rhs.listedBitrate ?? .infinity)
            case .higherBitrate:
                return (lhs.listedBitrate ?? 0) > (rhs.listedBitrate ?? 0)
            case .smallerFile:
                return (lhs.isPackageSize ? .infinity : lhs.size?.converted(to: .bytes).value ?? .infinity)
                    < (rhs.isPackageSize ? .infinity : rhs.size?.converted(to: .bytes).value ?? .infinity)
            case .addonOrder:
                return false
            }
        }

        /// The first order that tells the two apart decides; later ones break its ties.
        public static func precedes(_ lhs: StreamDetails, _ rhs: StreamDetails, by orders: [SortOrder]) -> Bool {
            for order in orders {
                if order.precedes(lhs, rhs) { return true }
                if order.precedes(rhs, lhs) { return false }
            }
            return false
        }
    }

    public var resolution: Resolution?
    /// "Dolby Vision", "HDR10+", "HDR10" or "HLG", best first; a file can carry several.
    public var dynamicRange: [String] = []
    public var codec: String?
    /// The format, then Atmos, then the channel layout: "TrueHD", "Atmos", "7.1".
    public var audio: [String] = []
    /// Where the release came from: "Remux", "BluRay", "WEB-DL", "WEB" or "HDTV".
    public var releaseType: String?
    public var size: Measurement<UnitInformationStorage>?
    public var isPackageSize = false
    /// Only the protocol's explicit videoSize identifies the individual playable file.
    public var fileSize: Int64?
    /// The addon's explicitly reported video/overall bitrate, in bits per second.
    public var bitrate: Double?
    /// The file size spread over the title's runtime, for the many addons that report no
    /// bitrate. Never taken from a season-pack total.
    public var estimatedBitrate: Double?
    /// Debrid services mark files they already hold; others have to be fetched first and
    /// often stall. Nil when the addon doesn't say.
    public var isCached: Bool?

    /// `runtime`, in seconds, lets a bitrate be estimated from the file size.
    public init(_ stream: StreamSource, runtime: TimeInterval? = nil) {
        let text = [stream.name, stream.title, stream.description, stream.behaviorHints?.filename]
            .compactMap { $0 }
            .joined(separator: "\n")
        self.init(text: text)
        if let bytes = stream.behaviorHints?.videoSize, bytes > 0 {
            fileSize = bytes
            size = Measurement(value: Double(bytes), unit: .bytes)
            isPackageSize = false
        }
        if bitrate == nil, let runtime { estimateBitrate(runtime: runtime) }
    }

    /// No single video file comes near the top (UHD Blu-ray peaks at 128 Mbps), and nothing
    /// watchable is below the bottom, so an estimate outside means the size was really a pack
    /// or a sample, or the runtime is wrong.
    static let plausibleEstimatedBitrates: ClosedRange<Double> = 200_000...150_000_000

    private mutating func estimateBitrate(runtime: TimeInterval) {
        guard !isPackageSize, runtime.isFinite, runtime > 0,
              let bytes = size?.converted(to: .bytes).value, bytes > 0 else { return }
        let rate = bytes * 8 / runtime
        estimatedBitrate = Self.plausibleEstimatedBitrates.contains(rate) ? rate : nil
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

        if has(/\btrue[ -]?hd\b/) {
            audio.append("TrueHD")
        } else if has(/\bdts[ -]?(hd|x|ma)\b/) {
            audio.append("DTS-HD")
        } else if has(/\bdts(?![a-z])/) {
            audio.append("DTS")
        } else if has(/\b(ddp|dd\+|e-?ac-?3)/) {
            audio.append("DD+")
        } else if has(/\b(dd|ac-?3)(?![a-z])/) {
            audio.append("DD")
        } else if has(/\baac(?![a-z])/) {
            audio.append("AAC")
        }
        if has(/\batmos\b/) { audio.append("Atmos") }
        // Written after the format ("DDP5.1"), and not to be confused with a size ("25.1 GB").
        if let channels = text.firstMatch(of: /(?:^|[^\d.,])([257])\.([01])(?!\d|\s*[GMT]i?B)/) {
            audio.append("\(channels.1).\(channels.2)")
        }

        releaseType = if has(/\bremux\b/) { "Remux" }
            else if has(/\b(blu-?ray|bdrip|brrip)\b/) { "BluRay" }
            else if has(/\bweb[ .-]?dl\b/) { "WEB-DL" }
            else if has(/\bweb([ .-]?rip)?\b/) { "WEB" }
            else if has(/\bhdtv\b/) { "HDTV" }
            else { nil }

        let reportedSizes = text.matches(of: /(\d+(?:[.,]\d+)?)\s*(TB|TiB|GB|GiB|MB|MiB)\b/.ignoresCase())
        if reportedSizes.count == 1, let match = reportedSizes.first,
           let value = Double(match.1.replacingOccurrences(of: ",", with: ".")) {
            let unit: UnitInformationStorage = switch match.2.uppercased() {
            case "TB": .terabytes
            case "TIB": .tebibytes
            case "GB": .gigabytes
            case "GIB": .gibibytes
            case "MB": .megabytes
            case "MIB": .mebibytes
            default: .gigabytes
            }
            size = Measurement(value: value, unit: unit)
            isPackageSize = has(/\b(season[ .-]*pack|complete[ .-]*(series|season)|[sS]\d{1,2}[ .-]*[sS]\d{1,2})\b/)
        }

        // A bitrate unit identifies a rate, unlike a file size or release-name number.
        // Conflicting reports (often separate audio/video rates) are left unknown.
        let bitrateText = text.components(separatedBy: .newlines).filter { line in
            !line.contains(/\b(audio|aac|dts|true[ -]?hd|opus|mp3|ddp?|e-?ac-?3)(?![a-z])/.ignoresCase())
                || line.contains(/\b(video|overall|total)\b/.ignoresCase())
        }.joined(separator: "\n")
        let reportedBitrates = bitrateText.matches(of: /(?:^|[^\d.,-])(\d+(?:[.,]\d+)?)\s*([kKmMgG])(?:bps|bit\/s|b\/s)\b/)
            .compactMap { match -> Double? in
                guard let value = Double(match.1.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
                let multiplier: Double = switch match.2.lowercased() {
                case "k": 1_000
                case "g": 1_000_000_000
                default: 1_000_000
                }
                let rate = value * multiplier
                return rate.isFinite ? rate : nil
            }
        if let first = reportedBitrates.first, reportedBitrates.allSatisfy({ $0 == first }) {
            bitrate = first
        }

        // "[RD+]" is Torrentio's and AIOStreams' mark for a cached file, "[RD download]"
        // or an hourglass for one that isn't; "⚡" is used for cached by several addons.
        if has(/\[[a-z]{2}\+\]|⚡|\bcached\b/) && !has(/\buncached\b/) {
            isCached = true
        } else if has(/\[[a-z]{2} download\]|⏳|\buncached\b/) {
            isCached = false
        }
    }

    /// "HEVC · Dolby Vision · TrueHD Atmos 7.1": how the file will look and sound. Only the
    /// best dynamic range is named, since the others are its fallbacks.
    public var summary: String? {
        let audio = audio.isEmpty ? nil : audio.joined(separator: " ")
        let kept = [codec, dynamicRange.first, audio].compactMap { $0 }
        return kept.isEmpty ? nil : kept.joined(separator: " · ")
    }

    /// "58.2 GB".
    public var sizeLabel: String? {
        size.map { $0.formatted(.byteCount(style: .file)) + (isPackageSize ? " pack" : "") }
    }

    /// The reported bitrate, else the estimate: what the list sorts and caps by.
    public var listedBitrate: Double? { bitrate ?? estimatedBitrate }

    /// "18 Mbps" as reported, or "≈18 Mbps" estimated from the size.
    public var bitrateLabel: String? {
        guard let rate = listedBitrate else { return nil }
        let mbps = (rate / 1_000_000).formatted(.number.precision(.fractionLength(bitrate == nil ? 0...0 : 0...1)))
        return (bitrate == nil ? "≈" : "") + mbps + " Mbps"
    }

    /// Series with unknown sizes or pack totals need a manual choice while a limit is enabled.
    public func permitsAutomaticPlayback(type: String, maximumFileSize: Int64) -> Bool {
        type != "series" || maximumFileSize <= 0 || fileSize.map { $0 <= maximumFileSize } == true
    }

    /// The headings the sources list groups by, best first; anything else, SD included,
    /// is listed under "Other".
    public static let listedResolutions: [Resolution] = [.ultraHD, .fullHD, .hd]

}
