import SwiftUI

/// Where a details section goes when the page has two columns.
enum DetailColumn {
    case main, side, full
}

private struct DetailColumnKey: LayoutValueKey {
    static let defaultValue = DetailColumn.main
}

extension View {
    func detailColumn(_ column: DetailColumn) -> some View {
        layoutValue(key: DetailColumnKey.self, value: column)
    }
}

/// The details page on a wide page (iPad, Mac): the hero and what follows from it on the left,
/// cast and information on the right, and full-width sections below both.
///
/// A layout rather than two sets of stacks: it swaps with a `VStackLayout` on rotation while the
/// sections keep their identity, so the chosen season and loaded reviews survive.
struct DetailColumnsLayout: Layout {
    /// Where the side column starts, low enough that the artwork above it stays clear.
    let sideTop: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // The scroll view around the page also asks for ideal and maximum sizes. Split into
        // columns, an unspecified or infinite width made the side column's width negative or
        // NaN, and the page's size with it; one column answers those.
        guard let width = proposal.width, width.isFinite else {
            let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
            return CGSize(width: sizes.map(\.width).max() ?? 0,
                          height: sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0)))
        }
        let widened = widenedCount(subviews, width: width)
        return CGSize(width: width, height: arrange(subviews, width: width, widening: widened) { _, _, _ in })
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widened = widenedCount(subviews, width: bounds.width)
        _ = arrange(subviews, width: bounds.width, widening: widened) { subview, origin, width in
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(width: width, height: nil))
        }
    }

    /// How many of the last side sections go full width instead. Without episodes the left
    /// column ends soon after the hero, and cast and information beside it left a tall empty
    /// space; a section moved below both columns is also shorter there, set in more columns.
    private func widenedCount(_ subviews: Subviews, width: CGFloat) -> Int {
        let sideCount = subviews.filter { $0[DetailColumnKey.self] == .side }.count
        let heights = (0...sideCount).map { arrange(subviews, width: width, widening: $0) { _, _, _ in } }
        // The first of equal heights, so sections stay beside the episodes unless moving them helps.
        return heights.indices.min { heights[$0] < heights[$1] } ?? 0
    }

    /// Calls `place` for each subview and returns the total height.
    private func arrange(_ subviews: Subviews, width: CGFloat, widening widened: Int,
                         place: (LayoutSubview, CGPoint, CGFloat) -> Void) -> CGFloat {
        // Enough on the left for Play and the three actions, even in a narrow window.
        let mainWidth = min(max((width * 0.58).rounded(), 580), width)
        let sideIndices = subviews.indices.filter { subviews[$0][DetailColumnKey.self] == .side }
        let moved = Set(sideIndices.suffix(widened))

        func stack(_ column: DetailColumn, x: CGFloat, width: CGFloat, from top: CGFloat) -> CGFloat {
            var y = top
            for index in subviews.indices {
                let placed = moved.contains(index) ? .full : subviews[index][DetailColumnKey.self]
                guard placed == column else { continue }
                place(subviews[index], CGPoint(x: x, y: y), width)
                y += subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height + spacing
            }
            return y
        }

        let main = stack(.main, x: 0, width: mainWidth, from: 0)
        let side = stack(.side, x: mainWidth, width: width - mainWidth, from: sideTop)
        return stack(.full, x: 0, width: width, from: max(main, side)) - spacing
    }
}
