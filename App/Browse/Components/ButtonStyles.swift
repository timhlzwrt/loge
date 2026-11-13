import LogeCore
import SwiftUI

/// The one accent-coloured call to action on a screen: Play or Resume. On iPhone and iPad
/// `.controlSize(.small)` draws it a size down, for a title page's centred row.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        #if os(tvOS)
        @Environment(\.isFocused) private var isFocused
        #elseif os(iOS)
        @Environment(\.controlSize) private var controlSize
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
        // 44 pt is as small as a button stays comfortable to tap.
        private var height: CGFloat { controlSize == .small ? 44 : 50 }
        private var font: Font { controlSize == .small ? .subheadline.weight(.semibold) : .headline }
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

/// Round, icon-only Liquid Glass buttons beside the primary one: Watch Later, More.
/// Drawn rather than using the `.glass` button style, which pads the circle beyond the
/// primary button's height. They follow `.controlSize(.small)` as that button does.
struct GlassIconButtonStyle: ButtonStyle {
    /// A short name under the icon while focused on Apple TV. Elsewhere the icons stand
    /// alone, and the Mac names them on hover.
    var caption: String?

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, caption: caption)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let caption: String?
        #if os(tvOS)
        @Environment(\.isFocused) private var isFocused
        #elseif os(iOS)
        @Environment(\.controlSize) private var controlSize
        #endif

        @ViewBuilder
        var body: some View {
            #if os(tvOS)
            if let caption {
                VStack(spacing: 12) {
                    icon
                    Text(caption)
                        .font(.system(size: 20, weight: .medium))
                        .fixedSize()
                        .frame(width: size)
                        .opacity(isFocused ? 1 : 0)
                        .accessibilityHidden(true)
                }
            } else {
                icon
            }
            #else
            icon
            #endif
        }

        private var icon: some View {
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
        private var size: CGFloat { controlSize == .small ? 44 : 50 }
        private var font: Font { controlSize == .small ? .body.weight(.semibold) : .title3.weight(.semibold) }
        #endif
    }
}

extension View {
    /// Artwork tiles that open something: tvOS lifts them as focus cards, elsewhere they respond
    /// to a pointer.
    func tileButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain).modifier(PointerHighlight())
        #endif
    }

    /// A 44 pt touch target for a one-line title that opens something ("Popular Movies ›",
    /// "Season 1 ⌄"), without moving what's around it.
    func titleTapTarget() -> some View {
        #if os(iOS)
        padding(.vertical, 8).contentShape(.rect).padding(.vertical, -8)
        #else
        self
        #endif
    }
}

/// Pointer feedback on artwork that opens something, which otherwise gives no sign in dense
/// rows of what can be clicked: the iPad pointer's highlight, a slight brightening on the Mac.
/// Apple TV has its focus effects instead.
struct PointerHighlight: ViewModifier {
    #if os(macOS)
    @State private var isHovered = false
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content.hoverEffect(.highlight)
        #elseif os(macOS)
        content
            .brightness(isHovered ? 0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
        #else
        content
        #endif
    }
}
