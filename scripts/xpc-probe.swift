// Tries to talk to Mooring's privileged helper from a process that is NOT the
// signed Mooring app. The helper must refuse it (docs/SPEC.md 1.5, 1.12).
//
//   swiftc scripts/xpc-probe.swift -o build/xpc-probe && build/xpc-probe
//
// (Compiled, not run with `swift`: the interpreter omits the method metadata
// NSXPCInterface needs.)
//
// Prints REJECTED (exit 0), ACCEPTED (exit 1: the caller check is broken) or
// NO RESPONSE (exit 2). Self-contained: it declares its own copy of the one
// method it calls, with the same selector as MooringHelperProtocol.version.

import Foundation

@objc protocol ProbeHelperProtocol {
    func version(reply: @escaping @Sendable (String) -> Void)
}

let connection = NSXPCConnection(machServiceName: "dev.mooring.helper", options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: ProbeHelperProtocol.self)
connection.resume()

let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    print("REJECTED: \(error.localizedDescription)")
    exit(0)
} as? ProbeHelperProtocol

proxy?.version { version in
    print("ACCEPTED: helper \(version) answered an unsigned caller")
    exit(1)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    print("NO RESPONSE after 5 s")
    exit(2)
}
dispatchMain()
