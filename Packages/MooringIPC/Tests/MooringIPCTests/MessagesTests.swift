import Foundation
import MooringIPC
import Testing

private func object(_ line: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
}

private func sampleLease(expiresAt: Date? = Date(timeIntervalSince1970: 1_800_000_000)) -> LeaseInfo {
    LeaseInfo(id: "job", owner: OwnerInfo(kind: "cli", name: "Claude Code"), reason: "Churn", level: "display",
              expiresAt: expiresAt, watchPid: 4121, ttl: 900)
}

@Test func acquireRequestMatchesTheSpecShape() throws {
    let request = Request(v: 1, id: "u1", op: .acquire, args: .acquire(AcquireArgs(kind: .lease, id: "job", level: "display",
        ttl: 900, watchPid: 4121, reason: "Churn", agent: "Claude Code")))
    let line = try WireCoding.encodeLine(request)
    let object = try object(line)
    #expect(object["v"] as? Int == 1 && object["op"] as? String == "acquire")
    #expect((object["args"] as? [String: Any])?["watchPid"] as? Int == 4121)
    #expect(line.last == UInt8(ascii: "\n") && line.filter { $0 == UInt8(ascii: "\n") }.count == 1)
    #expect(try WireCoding.decodeRequest(line).get() == request)
}

@Test func argsFollowTheOp() throws {
    let cases: [(Request, [String: Any])] = [
        (Request(v: 1, id: "a", op: .renew, args: .renew(RenewArgs(id: "job", ttl: 60))), ["id": "job", "ttl": 60]),
        (Request(v: 1, id: "b", op: .release, args: .release(ReleaseArgs(kind: .lease, id: "job", after: nil))),
         ["kind": "lease", "id": "job"]),
        (Request(v: 1, id: "c", op: .release, args: .release(ReleaseArgs(kind: .off, id: nil, after: 30))),
         ["kind": "off", "after": 30]),
        (Request(v: 1, id: "d", op: .status, args: .status), [:])
    ]
    for (request, expected) in cases {
        let line = try WireCoding.encodeLine(request)
        let args = try #require(try object(line)["args"] as? [String: Any])
        #expect(NSDictionary(dictionary: args) == NSDictionary(dictionary: expected), "\(request.op): \(args)")
        #expect(try WireCoding.decodeRequest(line).get() == request)
    }
}

@Test func nilOptionalsAreOmittedFromArgs() throws {
    let request = Request(v: 1, id: "x", op: .acquire, args: .acquire(AcquireArgs(kind: .on, id: nil, level: nil, ttl: nil,
        watchPid: nil, reason: nil, agent: nil)))
    let args = try #require(try object(WireCoding.encodeLine(request))["args"] as? [String: Any])
    #expect(args.keys.sorted() == ["kind"])
}

@Test func decodeRequestAcceptsATrailingNewlineOrNone() throws {
    let json = #"{"v":1,"id":"s","op":"status","args":{}}"#
    let expected = Request(v: 1, id: "s", op: .status, args: .status)
    #expect(try WireCoding.decodeRequest(Data(json.utf8)).get() == expected)
    #expect(try WireCoding.decodeRequest(Data((json + "\n").utf8)).get() == expected)
}

@Test func wrongVersionIsBadRequest() {
    guard case .failure(let error) = WireCoding.decodeRequest(Data(#"{"v":2,"id":"x","op":"status","args":{}}"#.utf8)) else {
        Issue.record("a v2 request decoded"); return
    }
    #expect(error.code == .badRequest)
    #expect(error.message == "Unsupported protocol version 2")
}

@Test func malformedAndOversizedLinesAreBadRequest() {
    #expect((try? WireCoding.decodeRequest(Data("{nope".utf8)).get()) == nil)
    #expect((try? WireCoding.decodeRequest(Data(repeating: UInt8(ascii: "a"), count: 70_000)).get()) == nil)
    if case .failure(let error) = WireCoding.decodeRequest(Data("{nope".utf8)) {
        #expect(error.code == .badRequest && error.message == "Malformed request")
    }
    if case .failure(let error) = WireCoding.decodeRequest(Data(repeating: UInt8(ascii: "a"), count: 70_000)) {
        #expect(error.code == .badRequest && error.message == "Request too long")
    }
    let unknownOp = Data(#"{"v":1,"id":"x","op":"win.list","args":{}}"#.utf8)
    #expect((try? WireCoding.decodeRequest(unknownOp).get()) == nil)
    let wrongArgs = Data(#"{"v":1,"id":"x","op":"renew","args":{}}"#.utf8)
    #expect((try? WireCoding.decodeRequest(wrongArgs).get()) == nil)
}

@Test func newlinesInStringsStayOnOneLine() throws {
    let request = Request(v: 1, id: "u", op: .acquire, args: .acquire(AcquireArgs(kind: .on, id: nil, level: nil, ttl: nil,
        watchPid: nil, reason: "a\nb\"c\u{7}", agent: nil)))
    let line = try WireCoding.encodeLine(request)
    #expect(line.filter { $0 == UInt8(ascii: "\n") }.count == 1)
    #expect(try WireCoding.decodeRequest(line).get() == request)
}

@Test func errorResponseRoundTrips() throws {
    let response = Response.failure(id: "u", .denied, "Lid mode for leases needs approval (stage 2c)")
    let line = try WireCoding.encodeLine(response)
    let decoded = try WireCoding.decodeResponse(line, op: .acquire)
    #expect(decoded == response && decoded.ok == false)
    let json = try object(line)
    #expect(json["result"] == nil && json["ok"] as? Bool == false)
    #expect((json["error"] as? [String: Any])?["code"] as? String == "denied")
}

@Test func acquireResultIsEncodedWithoutATag() throws {
    let response = Response.success(id: "r", .acquire(AcquireResult(lease: sampleLease(), clamped: false)))
    let line = try WireCoding.encodeLine(response)
    let result = try #require(try object(line)["result"] as? [String: Any])
    #expect(result.keys.sorted() == ["clamped", "lease"])
    #expect(try WireCoding.decodeResponse(line, op: .acquire) == response)
}

@Test func resultsRoundTripForEveryOp() throws {
    let responses: [(Op, Response)] = [
        (.renew, .success(id: "1", .renew(sampleLease()))),
        (.release, .success(id: "2", .release(ReleaseResult(released: true)))),
        (.acquire, .success(id: "3", .acquire(AcquireResult(lease: sampleLease(expiresAt: nil), clamped: true))))
    ]
    for (operation, response) in responses {
        #expect(try WireCoding.decodeResponse(WireCoding.encodeLine(response), op: operation) == response)
    }
}

@Test func statusResultRoundTripsWithDates() throws {
    let status = StatusResult(summary: "On · screen on · 1h left", effective: LevelInfo(system: true, display: true, lid: false),
        systemAssertion: true,
        displayAssertion: true, lidSleepDisabled: false, helperSleepDisabled: nil, wantsLid: false,
        leases: [sampleLease(), sampleLease(expiresAt: nil)], power: PowerInfo(onAC: false, batteryPercent: nil),
        thermal: "nominal", lidClosed: nil, helper: "notRegistered", suspensions: ["battery"])
    let response = Response.success(id: "st", .status(status))
    let line = try WireCoding.encodeLine(response)
    let text = try #require(String(bytes: line, encoding: .utf8))
    #expect(text.contains(#""expiresAt":"2027-01-15T08:00:00Z""#))
    let result = try #require(try object(line)["result"] as? [String: Any])
    #expect(result["summary"] as? String == "On · screen on · 1h left")
    for key in ["helperSleepDisabled", "lidClosed"] { #expect(result[key] is NSNull, "\(key) should be an explicit null") }
    #expect((result["power"] as? [String: Any])?["batteryPercent"] is NSNull)
    let leases = try #require(result["leases"] as? [[String: Any]])
    #expect(leases[1]["expiresAt"] is NSNull)
    let decoded = try WireCoding.decodeResponse(line, op: .status)
    #expect(decoded == response)
    guard case .status(let roundTripped)? = decoded.result else { Issue.record("not a status result"); return }
    #expect(roundTripped.leases[0].expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
}

@Test func responseWithoutExpectedPayloadFailsToDecode() {
    let missingResult = Data(#"{"v":1,"id":"x","ok":true}"#.utf8)
    #expect(throws: (any Error).self) { try WireCoding.decodeResponse(missingResult, op: .status) }
    let missingError = Data(#"{"v":1,"id":"x","ok":false}"#.utf8)
    #expect(throws: (any Error).self) { try WireCoding.decodeResponse(missingError, op: .status) }
}
