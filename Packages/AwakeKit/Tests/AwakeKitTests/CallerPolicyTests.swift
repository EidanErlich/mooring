import AwakeKit
import Testing

struct CallerPolicyTests {
    @Test func trustedOpsMayRunUntilTurnedOffWithLid() throws {
        #expect(try CallerPolicy.checkAcquire(kind: .trusted, id: "cli", level: AwakeLevel(display: false, lid: true), ttl: nil,
            watched: false, liveLeaseCount: 0, exists: false).get() == nil)
    }

    @Test func namedLeasesNeedATTLOrAWatch() {
        let result = CallerPolicy.checkAcquire(kind: .named, id: "job", level: .system, ttl: nil, watched: false,
            liveLeaseCount: 0, exists: false)
        #expect(result == .failure(.badRequest("A lease needs --ttl or --watch-pid")))
    }

    @Test func namedLeasesAreCappedAtFourHours() throws {
        #expect(try CallerPolicy.checkAcquire(kind: .named, id: "job", level: .system, ttl: 10 * 3600, watched: false,
            liveLeaseCount: 0, exists: false).get() == 4 * 3600)
        #expect(try CallerPolicy.checkAcquire(kind: .named, id: "job", level: .system, ttl: nil, watched: true,
            liveLeaseCount: 0, exists: false).get() == 4 * 3600)
    }

    @Test func namedLidIsNoLongerDeniedByPolicy() throws {
        let level = AwakeLevel(display: false, lid: true)
        #expect(try CallerPolicy.checkAcquire(kind: .named, id: "job", level: level, ttl: 600,
            watched: false, liveLeaseCount: 0, exists: false).get() == 600)
    }

    @Test func reservedAndInvalidIDsAreRefused() {
        for id in ["menu", "lid-session", "cli", "app-12", "anchor-9", "", "has space", String(repeating: "a", count: 65), "a/b"] {
            guard case .failure(.badRequest) = CallerPolicy.checkAcquire(kind: .named, id: id, level: .system, ttl: 60,
                watched: false, liveLeaseCount: 0, exists: false) else { Issue.record("\(id) allowed"); continue }
        }
        #expect(CallerPolicy.isValidNamedID("claude-abc_1.2"))
        #expect(CallerPolicy.checkAcquire(kind: .named, id: "menu", level: .system, ttl: 60, watched: false,
            liveLeaseCount: 0, exists: false) == .failure(.badRequest("menu is reserved")))
        #expect(CallerPolicy.checkAcquire(kind: .named, id: "has space", level: .system, ttl: 60, watched: false,
            liveLeaseCount: 0, exists: false) == .failure(.badRequest("Invalid lease id")))
    }

    @Test func thirtyThirdLeaseIsDeniedButRenewalsPass() {
        #expect(CallerPolicy.checkAcquire(kind: .trusted, id: "cli", level: .system, ttl: nil, watched: false,
            liveLeaseCount: 32, exists: false) == .failure(.denied("Too many leases (32)")))
        #expect((try? CallerPolicy.checkAcquire(kind: .named, id: "job", level: .system, ttl: 60, watched: false,
            liveLeaseCount: 32, exists: true).get()) != nil)
    }

    @Test func reasonsAreCleaned() {
        #expect(CallerPolicy.cleanReason("  fix\ntests\u{7}\t ") == "fixtests")
        #expect(CallerPolicy.cleanReason(String(repeating: "x", count: 100)).count == 80)
        #expect(CallerPolicy.cleanAgentName(String(repeating: "y", count: 50)).count == 40)
    }
}
