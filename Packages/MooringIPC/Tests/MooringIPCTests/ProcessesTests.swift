import Testing
@testable import MooringIPC

/// A `KERN_PROCARGS2` buffer: argc, the executable path, NUL padding, then each argument NUL-terminated.
private func procargs(argc: Int32, executable: String, padding: Int = 3, _ arguments: [String]) -> [UInt8] {
    var bytes = withUnsafeBytes(of: argc.littleEndian) { Array($0) }
    bytes += Array(executable.utf8) + [UInt8](repeating: 0, count: 1 + padding)
    for argument in arguments { bytes += Array(argument.utf8) + [0] }
    return bytes
}

@Test func procargsParsingReadsTheArguments() {
    let buffer = procargs(argc: 2, executable: "/usr/local/bin/node", ["node", "/usr/local/bin/claude"]) + Array("PATH=/bin\0".utf8)
    // The environment after argv is left out.
    #expect(SystemProcessTable.parseArguments(buffer) == ["node", "/usr/local/bin/claude"])
    #expect(SystemProcessTable.parseArguments(procargs(argc: 0, executable: "/bin/x", [])) == [])
}

@Test func procargsParsingHandlesGarbage() {
    // Too short for argc.
    #expect(SystemProcessTable.parseArguments([]) == nil)
    #expect(SystemProcessTable.parseArguments([2, 0]) == nil)
    // A negative argc.
    #expect(SystemProcessTable.parseArguments(procargs(argc: -1, executable: "/bin/x", ["x"])) == nil)
    // An executable path with no NUL after it.
    let noNUL = withUnsafeBytes(of: Int32(1).littleEndian) { Array($0) } + Array("/bin/node".utf8)
    #expect(SystemProcessTable.parseArguments(noNUL) == nil)
    // Only padding after the path.
    #expect(SystemProcessTable.parseArguments(procargs(argc: 2, executable: "/bin/node", padding: 8, [])) == [])
    // argc claims more strings than there are, and the last one is cut off before its NUL.
    let truncated = procargs(argc: 3, executable: "/bin/node", ["node"]) + Array("/usr/local/bi".utf8)
    #expect(SystemProcessTable.parseArguments(truncated) == ["node"])
    // A huge argc can't read past the end.
    let huge = procargs(argc: .max, executable: "/bin/node", ["node", "a"])
    #expect(SystemProcessTable.parseArguments(huge) == ["node", "a"])
}
