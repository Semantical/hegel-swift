/// An error reported by the Hegel runtime or its Swift binding.
public struct HegelError: Error, CustomStringConvertible, Sendable {
    public var description: String

    public init(_ description: String) {
        self.description = description
    }
}
