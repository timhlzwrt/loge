import SwiftUI

/// The canvas with amber light falling into one corner, on pages without artwork.
struct PageGlow: View {
    var color: Color = PageGlow.amber
    var center = UnitPoint(x: 0.85, y: 0.06)
    var strength = 0.32

    /// The amber of the retired accent colours.
    static let amber = Color(red: 0.96, green: 0.72, blue: 0.25)

    var body: some View {
        RadialGradient(colors: [color.opacity(strength), .clear], center: center,
                       startRadius: 0, endRadius: Self.radius)
            .background(Color.canvas)
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.6), value: color)
    }

    #if os(tvOS)
    static let radius: CGFloat = 900
    #elseif os(macOS)
    static let radius: CGFloat = 420
    #else
    static let radius: CGFloat = 460
    #endif
}
