#if os(macOS)
import SwiftUI

/// The Mac's Playback menu. Space is left to the player window itself, since as a menu
/// shortcut it would also swallow spaces typed into the search field.
struct PlaybackCommands: Commands {
    let playback: PlaybackSession

    var body: some Commands {
        CommandMenu("Playback") {
            let player = playback.player
            Button(player?.status == .playing ? "Pause" : "Play") { player?.togglePause() }
                .disabled(player == nil)
            Divider()
            Button("Skip Back 10 Seconds") { player?.seek(by: -10) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(player == nil)
            Button("Skip Forward 10 Seconds") { player?.seek(by: 10) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(player == nil)
            Button("Next Episode", action: playback.playNext)
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
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
                .keyboardShortcut(".", modifiers: .command)
                .disabled(player == nil)
        }
    }
}
#endif
