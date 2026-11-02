import Foundation

/// The App Group shared by Loge and its Top Shelf extension. Sideloading tools append the team ID
/// to the group's name, so the real name is read from the provisioning profile in the bundle.
enum AppGroup {
    static let identifier: String? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let profile = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return nil }
        // Each bundle also gets a default group named after itself; the shared one is the shortest.
        return groups.filter { $0.hasPrefix("group.li.tjh.MediaApp") }.min { $0.count < $1.count }
    }()

    static let testKey = "topShelfTest"
    static let testFile = "topShelfTest.txt"
}
