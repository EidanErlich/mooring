import MooringIPC
import Testing

@Test func wireProtocolIsVersion1() {
    #expect(WireProtocol.version == 1)
}

@Test func defaultSocketPathIsInApplicationSupport() {
    let path = WireProtocol.defaultSocketPath
    #expect(path.hasPrefix("/"))
    #expect(path.hasSuffix("/Library/Application Support/Mooring/mooring.sock"))
    #expect(path.utf8.count < 104)
}
