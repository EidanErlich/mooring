import Foundation
import Testing
@testable import Mooring

/// Parsing `mooring://` links (stage 2c-2).
struct MooringLinkTests {
    private func parse(_ text: String) throws -> Result<LinkAction, LinkError> {
        MooringLink.parse(try #require(URL(string: text)))
    }

    @Test func onWithAllParams() throws {
        let result = try parse("mooring://on?for=1h30m&level=lid&reason=Big%20build%20%F0%9F%9A%80")
        #expect(result == .success(.on(level: "lid", duration: 5400, reason: "Big build 🚀")))
    }

    @Test func onBare() throws {
        #expect(try parse("mooring://on") == .success(.on(level: nil, duration: nil, reason: nil)))
    }

    @Test func off() throws {
        #expect(try parse("mooring://off") == .success(.off))
    }

    @Test func toggleWithParams() throws {
        let result = try parse("mooring://toggle?for=15m&level=display")
        #expect(result == .success(.toggle(level: "display", duration: 900, reason: nil)))
    }

    @Test func uppercaseActionParses() throws {
        #expect(try parse("mooring://ON") == .success(.on(level: nil, duration: nil, reason: nil)))
    }

    @Test func trailingSlashParses() throws {
        #expect(try parse("mooring://on/") == .success(.on(level: nil, duration: nil, reason: nil)))
    }

    @Test func lastRepeatedParamWins() throws {
        let result = try parse("mooring://on?for=1h&for=2h&level=lid&level=system&reason=a&reason=b")
        #expect(result == .success(.on(level: "system", duration: 7200, reason: "b")))
    }

    @Test func unknownAction() throws {
        let result = try parse("mooring://onn")
        #expect(result == .failure(.unknownAction("onn")))
        #expect(LinkError.unknownAction("onn").message == "unknown action 'onn'")
    }

    @Test func badDuration() throws {
        let result = try parse("mooring://on?for=soon")
        #expect(result == .failure(.badDuration))
        #expect(LinkError.badDuration.message == "'for' must look like 30m or 1h30m")
    }

    @Test func badLevel() throws {
        let result = try parse("mooring://on?level=lidd")
        #expect(result == .failure(.badLevel("lidd")))
        #expect(LinkError.badLevel("lidd").message == "unknown level 'lidd'")
    }

    @Test func displayLidLevelParses() throws {
        let result = try parse("mooring://on?level=display,lid")
        #expect(result == .success(.on(level: "display,lid", duration: nil, reason: nil)))
    }
}
