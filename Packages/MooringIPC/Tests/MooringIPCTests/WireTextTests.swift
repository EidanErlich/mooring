import MooringIPC
import Testing

@Test func durations() {
    #expect(WireText.parseDuration("90s") == 90 && WireText.parseDuration("15m") == 900)
    #expect(WireText.parseDuration("2h") == 7200 && WireText.parseDuration("1h30m") == 5400)
    #expect(WireText.parseDuration("1h30m15s") == 5415)
    for bad in ["", "5", "0s", "-1m", "2d", "h", "1h1h", "1.5h", "30m1h", "1h 30m", " 5m", "0h30m", "1h0m", "5m5", "٣m"] {
        #expect(WireText.parseDuration(bad) == nil, "\(bad) should be rejected")
    }
    #expect(WireText.parseDuration("99999999999999999999h") == nil)
}

@Test func levels() {
    #expect(WireText.parseLevel("system")! == (false, false) && WireText.parseLevel("lid")! == (false, true))
    #expect(WireText.parseLevel("display,lid")! == (true, true) && WireText.parseLevel("bogus") == nil)
    #expect(WireText.parseLevel("lid,display")! == (true, true) && WireText.parseLevel("display")! == (true, false))
    for bad in ["", "Display", "LID", "display,", "display, lid", "system,lid", "display,display"] {
        #expect(WireText.parseLevel(bad) == nil, "\(bad) should be rejected")
    }
    #expect(WireText.levelName(display: true, lid: true) == "display,lid")
    #expect(WireText.levelName(display: false, lid: false) == "system")
    #expect(WireText.levelName(display: true, lid: false) == "display")
    #expect(WireText.levelName(display: false, lid: true) == "lid")
}

@Test func exitCodes() {
    #expect(WireText.exitCode(for: .badRequest) == 1 && WireText.exitCode(for: .notFound) == 1)
    #expect(WireText.exitCode(for: .guardrail) == 2 && WireText.exitCode(for: .denied) == 2)
    #expect(WireText.exitCode(for: .internal) == 4 && WireText.unreachableExitCode == 3)
}
