import Foundation
import Testing
@testable import LogeCore

struct AddonManifestTests {
    @Test func decodesCinemeta() throws {
        let manifest = try decodeFixture("cinemeta-manifest", as: AddonManifest.self)

        #expect(manifest.id == "com.linvo.cinemeta")
        #expect(manifest.resources.map(\.name).contains("meta"))
        #expect(manifest.catalogs.contains { $0.type == "movie" && $0.id == "top" })
    }

    @Test func decodesObjectResources() throws {
        let manifest = try decodeFixture("stream-addon-manifest", as: AddonManifest.self)

        #expect(manifest.resources == [
            .init(name: "catalog"),
            .init(name: "stream", types: ["movie", "series"], idPrefixes: ["tt", "kitsu"]),
        ])
    }
}
