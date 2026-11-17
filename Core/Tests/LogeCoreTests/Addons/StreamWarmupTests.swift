import Foundation
import Testing
@testable import LogeCore

struct StreamWarmupTests {
    @Test func asksEachLinkOnceWithinTheInterval() async {
        let warmup = StreamWarmup()
        let stream = StreamSource(name: "[RD+] Comet", url: "https://comet.example/playback/a")
        let start = Date.now
        #expect(await warmup.claim(stream, now: start) != nil)
        #expect(await warmup.claim(stream, now: start.addingTimeInterval(60)) == nil)
        #expect(await warmup.claim(stream, now: start.addingTimeInterval(31 * 60)) != nil)
    }

    @Test func neverAsksForAnUncachedOrIndirectSource() async {
        let warmup = StreamWarmup()
        #expect(await warmup.claim(StreamSource(name: "[RD download] Comet", url: "https://comet.example/playback/b")) == nil)
        #expect(await warmup.claim(StreamSource(url: "magnet:?xt=urn:btih:abc")) == nil)
        // Addons that don't say either way are asked.
        #expect(await warmup.claim(StreamSource(url: "https://cdn.example/c.mkv")) != nil)
    }
}
