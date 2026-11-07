import Foundation

/// The app's highlight colour, by name. The app decides how each one is drawn.
public enum Accent: String, CaseIterable, Codable, Identifiable, Sendable {
    case white, amber, coral, mint, sky

    public static let storageKey = "accentColor"
    public var id: Self { self }
    public var name: String { rawValue.capitalized }
}
