import AwakeKit
import Defaults

extension AwakeSettings: @retroactive Defaults.Serializable {}

extension Defaults.Keys {
    /// Everything the awake engine reads from Settings, stored as one Codable value.
    static let awake = Key<AwakeSettings>("awake", default: AwakeSettings())
    /// Settings → General: left click opens the dropdown, right click toggles.
    static let swapClickActions = Key<Bool>("swapClickActions", default: false)
}
