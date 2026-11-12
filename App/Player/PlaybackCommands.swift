#if os(macOS)
import SwiftUI

/// The Mac's Playback menu. Space is left to the player window itself, since as a menu
/// shortcut it would also swallow spaces typed into the search field. The other shortcuts
/// apply only while the player window is key: ⌘←, ⌘→ and ⌘. also move the cursor and cancel
/// in text fields, and the menu would take them first.
struct PlaybackCommands: Commands {
    let playback: PlaybackSession
    @FocusedValue(\.isPlayerWindow) private var isPlayerWindow

    var body: some Commands {
        CommandMenu("Playback") {
            let player = playback.player
            Button(player?.status == .playing ? "Pause" : "Play") { player?.togglePause() }
                .disabled(player == nil)
            Divider()
            Button("Skip Back 10 Seconds") { player?.seek(by: -10) }
                .keyboardShortcut(inPlayer(.leftArrow, modifiers: .command))
                .disabled(player == nil)
            Button("Skip Forward 10 Seconds") { player?.seek(by: 10) }
                .keyboardShortcut(inPlayer(.rightArrow, modifiers: .command))
                .disabled(player == nil)
            Button("Next Episode", action: playback.playNext)
                .keyboardShortcut(inPlayer(.rightArrow, modifiers: [.command, .shift]))
                .disabled(playback.next == nil)
            Divider()
            Button("Choose Source…", action: playback.chooseSource)
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!playback.canChooseSource)
            Button(player?.isZoomedToFill == true ? "Fit to Screen" : "Zoom to Fill") {
                player?.setZoomToFill(player?.isZoomedToFill != true)
            }
            .disabled(player == nil)
            Divider()
            Button("Picture in Picture") { playback.pictureInPicture?.start() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(playback.pictureInPicture?.isPossible != true)
            Button("Stop Playback", action: playback.end)
                .keyboardShortcut(inPlayer(".", modifiers: .command))
                .disabled(player == nil)
        }
    }

    private func inPlayer(_ key: KeyEquivalent, modifiers: EventModifiers) -> KeyboardShortcut? {
        isPlayerWindow == true ? KeyboardShortcut(key, modifiers: modifiers) : nil
    }
}

private struct PlayerWindowKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    /// Published by the player screen, so it's set while the player window is key.
    var isPlayerWindow: Bool? {
        get { self[PlayerWindowKey.self] }
        set { self[PlayerWindowKey.self] = newValue }
    }
}
#endif
