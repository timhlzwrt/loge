import Foundation
import Testing

/// The app, its package and the SideStore feed each state the minimum OS by hand, and a
/// mismatch only shows once someone can't install a release.
struct DeploymentMinimumsTests {
    private let repository = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../").standardizedFileURL

    private func read(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }

    @Test(arguments: ["iOS", "tvOS", "macOS"])
    func appAndPackageAgree(_ platform: String) throws {
        let project = try read("project.yml").firstMatch(of: try Regex("\(platform): \"([0-9.]+)\""))
        let package = try read("Core/Package.swift").firstMatch(of: try Regex("\\.\(platform)\\(\"([0-9.]+)\"\\)"))
        let target = try #require(project?.output[1].substring)
        #expect(package?.output[1].substring == target)
    }

    @Test func sideStoreFeedAdvertisesTheAppsMinimum() throws {
        let project = try read("project.yml").firstMatch(of: /iOS: "([0-9.]+)"/)
        let feed = try read("Tools/sidestore-source.py").firstMatch(of: /"minOSVersion": "([0-9.]+)"/)
        #expect(feed?.output.1 == (try #require(project?.output.1)))
    }
}
