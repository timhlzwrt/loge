import Foundation
import Testing

func decodeFixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}
