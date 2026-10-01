/// Applies lid mode (`pmset disablesleep`) through the privileged helper.
/// The app's `LidController` is the real one; tests use a fake.
@MainActor
public protocol LidApplying: AnyObject {
    /// The helper is approved and can be asked.
    var isAvailable: Bool { get }
    /// The `SleepDisabled` value the helper last confirmed; nil until first read.
    var applied: Bool? { get }
    /// A request is in flight; the engine doesn't send another until it finishes.
    var isBusy: Bool { get }
    /// Called whenever `applied`, `isAvailable` or `isBusy` changes.
    var onChange: (@MainActor () -> Void)? { get set }
    func apply(_ disabled: Bool)
    /// Re-reads `SleepDisabled` from the helper.
    func refresh()
}
