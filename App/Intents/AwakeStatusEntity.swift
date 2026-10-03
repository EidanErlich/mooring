import AppIntents
import AwakeKit
import Foundation
import MooringIPC

/// What "Get Awake Status" returns: the menu session's state, for Shortcuts to branch on or show.
struct AwakeStatusEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Awake Status"

    @Property(title: "Is On")
    var isOn: Bool

    @Property(title: "Summary")
    var summary: String

    @Property(title: "Level")
    var level: String

    @Property(title: "Ends At")
    var endsAt: Date?

    @Property(title: "Battery Percent")
    var batteryPercent: Int?

    @Property(title: "On Power")
    var onPower: Bool?

    init() {
        isOn = false
        summary = ""
        level = "off"
    }

    /// On means the menu's own session or a picked app's is live. The level and end are the menu session's.
    @MainActor
    init(_ status: StatusResult) {
        let menu = status.leases.first { $0.id == AwakeEngine.menuLeaseID }
        isOn = menu != nil || status.leases.contains { $0.id.hasPrefix("app-") }
        summary = status.summary
        level = menu?.level ?? "off"
        endsAt = menu?.expiresAt
        batteryPercent = status.power.batteryPercent
        onPower = status.power.onAC
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(summary)")
    }
}
