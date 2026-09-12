#if os(WASI)
import WASILibc

// The upstream static archive leaves these two C hooks for the host to supply.
@c(hegel_host_entropy_fill)
func hegelHostEntropyFill(_ bytes: UnsafeMutableRawPointer?, _ count: UInt) -> Int32 {
    guard count > 0 else { return 1 }
    guard let bytes = unsafe bytes, let count = Int(exactly: count) else { return 0 }

    var offset = 0
    while offset < count {
        // getentropy accepts at most 256 bytes per call.
        let length = min(256, count - offset)
        guard unsafe getentropy(bytes.advanced(by: offset), length) == 0 else { return 0 }
        offset += length
    }
    return 1
}

private let hegelClockOrigin = ContinuousClock.now

@c(hegel_host_monotonic_nanos)
func hegelHostMonotonicNanos() -> Int64 {
    // Hegel measures elapsed time, so the clock only needs a stable origin.
    let elapsed = hegelClockOrigin.duration(to: .now).components
    let (seconds, secondsOverflow) = elapsed.seconds.multipliedReportingOverflow(by: 1_000_000_000)
    let (nanos, nanosOverflow) = seconds.addingReportingOverflow(
        elapsed.attoseconds / 1_000_000_000
    )
    guard !secondsOverflow, !nanosOverflow else { return -1 }
    return nanos
}
#endif
