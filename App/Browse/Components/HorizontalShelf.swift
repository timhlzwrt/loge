import SwiftUI

/// Mouse navigation on Mac, with the native touch and remote scrolling on other platforms.
struct HorizontalShelf<Content: View>: View {
    let label: String
    private let content: Content
    #if os(macOS)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition()
    @State private var geometry = ShelfGeometry()
    #endif

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal) { content }
            #if os(macOS)
            // `.hidden` still permits the system's always-visible setting to draw a track.
            .scrollIndicators(.never)
            .scrollPosition($position)
            .onScrollGeometryChange(for: ShelfGeometry.self) { ShelfGeometry($0) } action: { _, value in
                geometry = value
            }
            .overlay(alignment: .leading) {
                if geometry.offset > 1 {
                    pageButton(forward: false).padding(.leading, 2)
                }
            }
            .overlay(alignment: .trailing) {
                if geometry.offset < geometry.maximum - 1 {
                    pageButton(forward: true).padding(.trailing, 2)
                }
            }
            #else
            .scrollIndicators(.hidden)
            #endif
    }

    #if os(macOS)
    private func pageButton(forward: Bool) -> some View {
        Button {
            let distance = max(1, geometry.width - Metrics.gutter * 2)
            let target = min(geometry.maximum, max(0, geometry.offset + (forward ? distance : -distance)))
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                position.scrollTo(x: target)
            }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 44)
                .foregroundStyle(.white)
                .background(Color.canvas.opacity(0.96), in: .rect(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.14)) }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(forward ? "Next" : "Previous") \(label)")
        .help("\(forward ? "Next" : "Previous") \(label)")
    }

    private struct ShelfGeometry: Equatable {
        var offset: CGFloat = 0
        var width: CGFloat = 0
        var maximum: CGFloat = 0

        init() {}

        init(_ geometry: ScrollGeometry) {
            // Leading safe-area insets are included in offsets, but not in scroll targets.
            offset = geometry.contentOffset.x + geometry.contentInsets.leading
            width = geometry.containerSize.width
            maximum = max(0, geometry.contentSize.width - width)
        }
    }
    #endif
}
