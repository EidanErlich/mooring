// Stands in for the helper binary to answer docs/SPEC.md Appendix B: does
// launchd refuse to start a dev.mooring.helper that someone swapped inside the
// (user-writable) app bundle? If it runs, it leaves a marker with its uid.
//
//   swiftc scripts/lwcr-probe.swift -o build/lwcr-probe && codesign -s - -f build/lwcr-probe
import Foundation

let marker = "/tmp/mooring-lwcr-probe"
try? "uid \(getuid()) at \(Date())\n".write(toFile: marker, atomically: true, encoding: .utf8)
