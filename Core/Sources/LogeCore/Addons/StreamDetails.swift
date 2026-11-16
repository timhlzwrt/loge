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
    /// False for a picture known to be SDR, nil when the text doesn't say.
    public var isHDR: Bool?
    public var codec: String?
    /// The format, then Atmos, then the channel layout: "TrueHD", "Atmos", "7.1".
    public var audio: [String] = []
    /// The audio languages the addon marks, as ISO 639-1 codes from `LanguageCodes.common`;
    /// empty when it doesn't say, or only says "Multi".
    public var languages: [String] = []
    /// Where the release came from: "Remux", "BluRay", "WEB-DL", "WEB" or "HDTV".
    public var releaseType: String?
    public var size: Measurement<UnitInformationStorage>?
    public var isPackageSize = false
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
        // Release names tag HDR next to the resolution, so a resolution without a tag is SDR.
        isHDR = if !dynamicRange.isEmpty { true }
            else if resolution != nil || has(/\bsdr\b/) { false }
            else { nil }

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

        // Addons mark languages with flags ("🇬🇧 🇩🇪"); names would also match film titles
        // ("The French Dispatch"). The flag's region gives its main language.
        for character in text {
            let scalars = character.unicodeScalars.map(\.value)
            guard scalars.count == 2, scalars.allSatisfy((0x1F1E6...0x1F1FF).contains) else { continue }
            let region = String(String.UnicodeScalarView(scalars.compactMap { UnicodeScalar($0 - 0x1F1E6 + 65) }))
            let language = Locale.Language(identifier: Locale.Language(identifier: "und-\(region)").maximalIdentifier)
            if let code = language.languageCode?.identifier, LanguageCodes.common.contains(code), !languages.contains(code) {
                languages.append(code)
            }
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
        size.map { $0.formatted(.byteCount(style: .file).locale(.interface)) + (isPackageSize ? " pack" : "") }
    }

    /// The reported bitrate, else the estimate: what the list and autoplay cap by.
    public var listedBitrate: Double? { bitrate ?? estimatedBitrate }

    /// "18 Mbps" as reported, or "≈18 Mbps" estimated from the size.
    public var bitrateLabel: String? {
        guard let rate = listedBitrate else { return nil }
        let mbps = (rate / 1_000_000).formatted(.number.precision(.fractionLength(bitrate == nil ? 0...0 : 0...1)).locale(.interface))
        return (bitrate == nil ? "≈" : "") + mbps + " Mbps"
    }

    /// Whether the listed bitrate is within `maximumBitrate` Mbps (0 for no limit); nil when
    /// the bitrate isn't known.
    public func isWithin(maximumBitrate: Int) -> Bool? {
        guard maximumBitrate > 0 else { return true }
        return listedBitrate.map { $0 <= Double(maximumBitrate) * 1_000_000 }
    }

    /// The headings the sources list groups by, best first; anything else, SD included,
    /// is listed under "Other".
    public static let listedResolutions: [Resolution] = [.ultraHD, .fullHD, .hd]

    /// The share of the measured download speed a source's average bitrate may use: busy
    /// scenes run well above a file's average, and Wi-Fi speed wanders.
    public static let connectionHeadroom = 0.75

    /// The best source the connection keeps up with: the highest resolution, then one the
    /// debrid service holds, then the highest bitrate, among sources whose bitrate is known
    /// and within `connectionHeadroom` of `connectionSpeed` (bits per second). Nil when no
    /// listed source is too much for the connection, since then there's nothing to steer
    /// away from, or when none fits.
    public static func recommendedIndex(in sources: [StreamDetails], connectionSpeed: Double) -> Int? {
        let limit = connectionSpeed * connectionHeadroom
        guard limit > 0, sources.contains(where: { ($0.listedBitrate ?? 0) > limit }) else { return nil }
        return sources.indices
            .filter { sources[$0].listedBitrate.map { $0 <= limit } == true }
            .max { lhs, rhs in
                let (a, b) = (sources[lhs], sources[rhs])
                if a.resolution != b.resolution { return (a.resolution?.rawValue ?? 0) < (b.resolution?.rawValue ?? 0) }
                if (a.isCached != false) != (b.isCached != false) { return a.isCached == false }
                return (a.listedBitrate ?? 0) < (b.listedBitrate ?? 0)
            }
    }

}
