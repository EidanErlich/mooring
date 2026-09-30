import AwakeKit
import Defaults
import SwiftUI

/// Awake › Keep Awake: what a left click on the icon turns On with.
struct KeepAwakeSettingsPage: View {
    @Default(.awake) private var awake

    var body: some View {
        Form {
            Section("When I click the icon") {
                Picker("Keep", selection: Binding(
                    get: { ClickLevelOption(level: awake.clickLevel) },
                    set: { awake.clickLevel = $0.level }
                )) {
                    ForEach(ClickLevelOption.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("For", selection: Binding(
                    get: { AwakeDuration(interval: awake.clickDuration) },
                    set: { awake.clickDuration = $0.interval }
                )) {
                    ForEach(AwakeDuration.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("End my session after the Mac sleeps", isOn: $awake.endMenuLeaseAfterSleep)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Keep Awake")
    }
}
