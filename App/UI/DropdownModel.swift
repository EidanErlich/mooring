import AppKit
import AwakeKit
import Observation
import SwiftUI

/// State the dropdown keeps between openings.
@MainActor
@Observable
final class DropdownModel {
    /// The duration row picked last, for its checkmark.
    var lastPick = DurationPick.none
    /// Drives the menu's countdown timelines, which are paused while the menu is closed.
    private(set) var isOpen = false
    /// The id of the row under the menu's highlight, set from the menu delegate.
    var highlightedID: String?

    func menuDidOpen() {
        isOpen = true
    }

    func menuDidClose() {
        isOpen = false
        highlightedID = nil
    }
}

/// The duration row picked last and the expiry it produced. The checkmark follows
/// the pick only while the menu lease still has that expiry; any other change
/// (left click, restore, ✕, expiry) falls back to "Until turned off" when it applies.
struct DurationPick: Equatable {
    var duration: AwakeDuration?
    var expiresAt: Date?

    static let none = DurationPick(duration: nil, expiresAt: nil)

    func isChecked(_ row: AwakeDuration, menuLease: Lease?) -> Bool {
        guard let menuLease else { return false }
        if let duration, expiresAt == menuLease.expiresAt { return row == duration }
        return row == .untilTurnedOff && menuLease.expiresAt == nil
    }
}
