import Foundation
import MooringIPC
import Testing
@testable import MooringCLICore

private let posted = Response.success(id: "r", .notify(NotifyResult(posted: true)))

private func notifyArgs(_ request: Request?) -> NotifyArgs? {
    if case .notify(let args)? = request?.args { return args }
    return nil
}

@Test func notifySendsTitleAndBody() async {
    let harness = Harness(client: RecordingClient(reply: .success(posted)))
    #expect(await harness.run(["notify", "Done", "Build finished"]) == 0)
    #expect(harness.client.lastRequest == Request(
        v: 1, id: "req-1", op: .notify, args: .notify(NotifyArgs(title: "Done", body: "Build finished", client: nil))
    ))
    #expect(harness.client.lastLaunch == true)
    #expect(harness.capture.stdout == "Notified\n")
}

@Test func notifyBodyIsOptional() async {
    let harness = Harness(client: RecordingClient(reply: .success(posted)))
    #expect(await harness.run(["notify", "Done"]) == 0)
    #expect(notifyArgs(harness.client.lastRequest) == NotifyArgs(title: "Done", body: nil, client: nil))
}

@Test func notifyDeniedExitsTwoWithMessage() async {
    let reply = Response.failure(id: "r", .denied, "Rate-limited: try again in 12 s")
    let harness = Harness(client: RecordingClient(reply: .success(reply)))
    #expect(await harness.run(["notify", "Done"]) == 2)
    #expect(harness.capture.stderr == "mooring: Rate-limited: try again in 12 s\n")
    #expect(harness.capture.stdout.isEmpty)
}

@Test func notifyRequiresTitle() async {
    let harness = Harness(client: RecordingClient(reply: .success(posted)))
    #expect(await harness.run(["notify"]) == 1)
    #expect(harness.client.requests.isEmpty)
    #expect(!harness.capture.stderr.isEmpty)
}

@Test func notifyJSONPrintsTheResult() async {
    let harness = Harness(client: RecordingClient(reply: .success(posted)))
    #expect(await harness.run(["notify", "Done", "--json"]) == 0)
    #expect(harness.capture.stdout.contains(#""posted":true"#))
}
