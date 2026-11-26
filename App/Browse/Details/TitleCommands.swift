#if os(macOS)
import SwiftUI

/// What the menu bar's Title menu acts on: the title page in the key window.
struct TitleCommandActions {
    let playLabel: String
    let play: (() -> Void)?
    let isSaved: Bool
    let toggleSaved: () -> Void
    let chooseSource: (() -> Void)?
    let isWatched: Bool
    let toggleWatched: (() -> Void)?
}

private struct TitleCommandActionsKey: FocusedValueKey {
    typealias Value = TitleCommandActions
}

extension FocusedValues {
    var titleActions: TitleCommandActions? {
        get { self[TitleCommandActionsKey.self] }
        set { self[TitleCommandActionsKey.self] = newValue }
    }
}

/// The title page's buttons in the menu bar, with keys, as a Mac app offers them.
struct TitleCommands: Commands {
    @FocusedValue(\.titleActions) private var title

    var body: some Commands {
        CommandMenu("Title") {
            Button(title?.playLabel ?? "Play") { title?.play?() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(title?.play == nil)
            Button(title?.isSaved == true ? "Remove from Watch Later" : "Add to Watch Later") { title?.toggleSaved() }
                .keyboardShortcut("l")
                .disabled(title == nil)
            Button("Sources…") { title?.chooseSource?() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(title?.chooseSource == nil)
            Divider()
            Button(title?.isWatched == true ? "Mark as Unwatched" : "Mark as Watched") { title?.toggleWatched?() }
                .disabled(title?.toggleWatched == nil)
        }
    }
}
#endif
