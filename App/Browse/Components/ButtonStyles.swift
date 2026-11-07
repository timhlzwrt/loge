import LogeCore
import SwiftUI

/// The one accent-coloured call to action on a screen: Play or Resume.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        #if os(tvOS)
        @Environment(\.isFocused) private var isFocused
        #endif

        var body: some View {
            configuration.label
                .font(font)
                .labelStyle(PlayLabelStyle())
                .foregroundStyle(.black)
                .padding(.leading, height * 0.44)
                .padding(.trailing, height * 0.56)
                .frame(minHeight: height)
                .background(.tint, in: .capsule)
                .opacity(configuration.isPressed ? 0.8 : 1)
                #if os(tvOS)
                .scaleEffect(isFocused ? 1.06 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 24, y: 14)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                #endif
        }

        #if os(tvOS)
        private let height: CGFloat = 78
        private let font = Font.system(size: 27, weight: .semibold)
        #elseif os(macOS)
        private let height: CGFloat = 36
        private let font = Font.system(size: 14, weight: .semibold)
        #else
        private let height: CGFloat = 50
        private let font = Font.headline
        #endif
    }

    /// A smaller glyph than the text, as in the TV app.
    private struct PlayLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 8) {
                configuration.icon.imageScale(.small)
                configuration.title
            }
        }
    }
}

/// Round, icon-only Liquid Glass buttons beside the primary one: Watch Later, Choose a Source.
/// Drawn rather than using the `.glass` button style, which pads the circle beyond the
/// primary button's height.
struct GlassIconButtonStyle: ButtonStyle {
    /// Just the icon, no circle: a phone's row under a full-width Play, where a line of
    /// bubbles beneath the capsule looked busy.
    var isBare = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, isBare: isBare)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let isBare: Bool
        #if os(tvOS)
        @Environment(\.isFocused) private var isFocused
        #endif

        @ViewBuilder
        var body: some View {
            if isBare {
                configuration.label
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(height: 30)
                    .opacity(configuration.isPressed ? 0.5 : 1)
            } else {
                glassCircle
            }
        }

        private var glassCircle: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(font)
                .frame(width: size, height: size)
                .contentShape(.circle)
                #if os(tvOS)
                // Focus fills the circle, as the system's glass buttons do, in the accent.
                .foregroundStyle(isFocused ? .black : .white)
                .background(.tint.opacity(isFocused ? 1 : 0), in: .circle)
                .glassEffect(.regular, in: .circle)
                .scaleEffect(isFocused ? 1.06 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 24, y: 14)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                #else
                .foregroundStyle(.white)
                .glassEffect(.regular.interactive(), in: .circle)
                #endif
        }

        #if os(tvOS)
        private let size: CGFloat = 78
        private let font = Font.system(size: 27, weight: .semibold)
        #elseif os(macOS)
        private let size: CGFloat = 36
        private let font = Font.system(size: 14, weight: .semibold)
        #else
        private let size: CGFloat = 50
        private let font = Font.title3.weight(.semibold)
        #endif
    }
}

extension View {
    /// Artwork tiles that open something: tvOS lifts them as focus cards, elsewhere they stay unstyled.
    func tileButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
    }
}
