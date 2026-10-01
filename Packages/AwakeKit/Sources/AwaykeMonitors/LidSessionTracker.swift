// Adapted from Awayke@b502251: Awayke/LidSessionTracker.swift
//
//  LidSessionTracker.swift
//  Awayke
//
//  Small state machine for an "until the lid is reopened" session. Starting
//  while the lid is open must not expire immediately; it first waits for a
//  close, then expires on the following open.
//

public final class LidSessionTracker {

    public init() {}
    private enum State {
        case inactive
        case waitingForClose
        case waitingForOpen
    }

    private var state = State.inactive

    public var isActive: Bool {
        if case .inactive = state { return false }
        return true
    }

    public var isWaitingForClose: Bool {
        if case .waitingForClose = state { return true }
        return false
    }

    public func start(lidClosed: Bool?) {
        state = (lidClosed == true) ? .waitingForOpen : .waitingForClose
    }

    public func cancel() {
        state = .inactive
    }

    /// Returns true exactly once: when a started session observes the lid
    /// reopen after it has been closed.
    public func handle(lidClosed: Bool) -> Bool {
        switch (state, lidClosed) {
        case (.waitingForClose, true):
            state = .waitingForOpen
        case (.waitingForOpen, false):
            state = .inactive
            return true
        default:
            break
        }
        return false
    }
}
