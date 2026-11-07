import Foundation

extension AccountSync {
    public enum Status: Equatable, Sendable {
        case off, ready, waiting, syncing, upToDate, failed
        case choosingInitialSetup, choosingSettings, choosingPlayback, choosingSharedSettings, choosingRemaining
        /// A pending choice was previewed again because something changed before it applied.
        case choosingAgain(ChangedBy)
        case sharedSetupJoined, sharedSetupLeft, sharedSetupChanged

        public enum ChangedBy: Sendable { case thisDevice, anotherDevice, syncing }

        public var text: String {
            switch self {
            case .off: "Off"
            case .ready: "Ready to sync"
            case .waiting: "Changes waiting to sync"
            case .syncing: "Syncing…"
            case .upToDate: "Up to date"
            case .failed: "Couldn't sync"
            case .choosingInitialSetup: "Choose the initial setup"
            case .choosingSettings: "Choose conflicting settings"
            case .choosingPlayback: "Choose playback position"
            case .choosingSharedSettings: "Choose shared settings"
            case .choosingRemaining: "Choose remaining changes"
            case .choosingAgain(.thisDevice): "Changed on this device. Choose again."
            case .choosingAgain(.anotherDevice): "Changed on another device. Choose again."
            case .choosingAgain(.syncing): "Changed while syncing. Choose again."
            case .sharedSetupJoined: "Shared setup connected"
            case .sharedSetupLeft: "Shared setup disconnected"
            case .sharedSetupChanged: "Shared setup changed. Sync again."
            }
        }
    }
}
