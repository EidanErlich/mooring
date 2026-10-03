import Foundation
import MooringIPC
import Testing

@Test func notifyRequestRoundTrips() throws {
    let request = Request(v: 1, id: "n1", op: .notify, args: .notify(.init(title: "Done", body: "x")))
    let line = try WireCoding.encodeLine(request)
    #expect(try WireCoding.decodeRequest(line).get() == request)
    let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
    #expect(object["op"] as? String == "notify")
    let args = try #require(object["args"] as? [String: Any])
    #expect(args.keys.sorted() == ["body", "title"])
}

@Test func notifyResponseDecodes() throws {
    let line = Data(#"{"v":1,"id":"a","ok":true,"result":{"posted":true}}"#.utf8)
    let response = try WireCoding.decodeResponse(line, op: .notify)
    #expect(response.result == .notify(.init(posted: true)))
    let reencoded = try WireCoding.encodeLine(response)
    #expect(try WireCoding.decodeResponse(reencoded, op: .notify) == response)
}

@Test func acquireClientIsOptional() throws {
    let line = Data(#"{"v":1,"id":"a","op":"acquire","args":{"kind":"on"}}"#.utf8)
    guard case .acquire(let args) = try WireCoding.decodeRequest(line).get().args else {
        Issue.record("expected acquire args")
        return
    }
    #expect(args.client == nil)

    let withClient = AcquireArgs(kind: .lease, id: "j", level: nil, ttl: nil, watchPid: nil, reason: nil, agent: nil, client: "Cursor")
    let request = Request(v: 1, id: "b", op: .acquire, args: .acquire(withClient))
    #expect(try WireCoding.decodeRequest(WireCoding.encodeLine(request)).get() == request)
}
