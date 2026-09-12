/// Stable span identity, retained even when a generator's concrete recipe is erased.
package struct GeneratorLabel: Equatable, Sendable {
    package var rawValue: UInt64

    package init(_ name: String) {
        rawValue = 0xcbf2_9ce4_8422_2325
        for byte in name.utf8 {
            append(byte)
        }
    }

    package init(_ name: String, components: [Self]) {
        self.init(combining: [Self(name)] + components)
    }

    package init(combining labels: [Self]) {
        rawValue = 0xcbf2_9ce4_8422_2325
        // libhegel combines the little-endian bytes of each label using FNV-1a.
        // Do not use Swift's Hasher: its seed changes between processes.
        for label in labels {
            for shift in stride(from: 0, to: 64, by: 8) {
                append(UInt8(truncatingIfNeeded: label.rawValue >> shift))
            }
        }
    }

    private mutating func append(_ byte: UInt8) {
        rawValue = (rawValue ^ UInt64(byte)) &* 0x100_0000_01b3
    }
}
