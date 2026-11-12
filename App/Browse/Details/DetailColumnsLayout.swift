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

/// The details page on a wide iPad page: the hero and what follows from it on the left, cast and
/// information on the right, and full-width sections below both.
///
/// A layout rather than two sets of stacks: it swaps with a `VStackLayout` on rotation while the
/// sections keep their identity, so the chosen season and loaded reviews survive.
struct DetailColumnsLayout: Layout {
    /// Where the side column starts, low enough that the artwork above it stays clear.
    let sideTop: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: arrange(subviews, width: width) { _, _, _ in })
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        _ = arrange(subviews, width: bounds.width) { subview, origin, width in
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(width: width, height: nil))
        }
    }

    /// Calls `place` for each subview and returns the total height.
    private func arrange(_ subviews: Subviews, width: CGFloat,
                         place: (LayoutSubview, CGPoint, CGFloat) -> Void) -> CGFloat {
        // Enough on the left for Play and the three actions, even in a narrow window.
        let mainWidth = max((width * 0.58).rounded(), 580)

        func stack(_ column: DetailColumn, x: CGFloat, width: CGFloat, from top: CGFloat) -> CGFloat {
            var y = top
            for subview in subviews where subview[DetailColumnKey.self] == column {
                place(subview, CGPoint(x: x, y: y), width)
                y += subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height + spacing
            }
            return y
        }

        let main = stack(.main, x: 0, width: mainWidth, from: 0)
        let side = stack(.side, x: mainWidth, width: width - mainWidth, from: sideTop)
        return stack(.full, x: 0, width: width, from: max(main, side)) - spacing
    }
}
