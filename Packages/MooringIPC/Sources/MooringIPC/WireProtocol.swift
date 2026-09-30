/// The app ↔ CLI socket format (docs/SPEC.md 2.1). Every request and response
/// carries this value in its `v` field.
public enum WireProtocol {
    public static let version = 1
}
