import MediaCore
import SwiftUI

extension Color {
    /// Charcoal rather than black, so dark posters and backdrop edges stay visible.
    static let canvas = Color(red: 0.08, green: 0.08, blue: 0.09)
}

enum Metrics {
    #if os(tvOS)
    static let posterWidth: CGFloat = 220
    static let episodeWidth: CGFloat = 400
    // tvOS already insets content by its own safe area margins.
    static let gutter: CGFloat = 0
    static let rowSpacing: CGFloat = 40
    #elseif os(macOS)
    static let posterWidth: CGFloat = 140
    static let episodeWidth: CGFloat = 260
    static let gutter: CGFloat = 28
    static let rowSpacing: CGFloat = 16
    #else
    static let posterWidth: CGFloat = 112
    static let episodeWidth: CGFloat = 220
    static let gutter: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    #endif
}

/// Remote artwork that fills whatever frame it's given, cropping rather than
/// growing to the image's own size, with a quiet placeholder while loading or missing.
struct Artwork: View {
    let url: String?

    var body: some View {
        Color.white.opacity(0.06)
            .overlay {
                AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
            .clipped()
    }
}

/// A thin bar along the bottom of artwork showing how much has been watched,
/// or a checkmark once it's finished.
struct WatchProgressBar: View {
    let progress: WatchProgress

    var body: some View {
        if progress.isFinished {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .white)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .accessibilityLabel("Watched")
        } else {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.3))
                    Rectangle().fill(.white).frame(width: proxy.size.width * progress.fraction)
                }
            }
            .frame(height: 4)
            .accessibilityLabel("\(Int(progress.fraction * 100)) percent watched")
        }
    }
}

/// Fades a backdrop into the canvas so text placed over its lower part stays legible.
struct BackdropFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .canvas.opacity(0), location: 0.25),
                .init(color: .canvas.opacity(0.85), location: 0.6),
                .init(color: .canvas, location: 0.85),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// The addon's logo image for a title, falling back to the name as text.
struct TitleLogo: View {
    let logo: String?
    let name: String
    let maxHeight: CGFloat

    var body: some View {
        AsyncImage(url: logo.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .accessibilityLabel(name)
            case .failure:
                nameText
            default:
                // Reserve the space so the layout doesn't jump when the logo arrives.
                Color.clear.frame(height: maxHeight)
            }
        }
        .frame(maxHeight: maxHeight)
    }

    private var nameText: some View {
        Text(name)
            .font(.largeTitle.bold())
            .lineLimit(2)
            .minimumScaleFactor(0.6)
    }
}

/// "2008–2013 · Crime, Drama · 49 min · ★ 9.5"
struct InfoLine: View {
    let releaseInfo: String?
    let genres: [String]?
    let runtime: String?
    let rating: String?

    var body: some View {
        let parts = [releaseInfo, genres?.prefix(2).joined(separator: ", "), runtime]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let details = parts.joined(separator: " · ")
        let line: Text
        if let rating, !rating.isEmpty {
            let star = Text(Image(systemName: "star.fill")).foregroundStyle(.yellow)
            line = Text("\(details)\(parts.isEmpty ? "" : " · ")\(star) \(rating)")
        } else {
            line = Text(details)
        }
        return line
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

extension MetaPreview {
    var infoLine: InfoLine {
        InfoLine(releaseInfo: releaseInfo, genres: genres, runtime: runtime, rating: imdbRating)
    }
}

extension Meta {
    var infoLine: InfoLine {
        InfoLine(releaseInfo: releaseInfo, genres: genres, runtime: runtime, rating: imdbRating)
    }
}
