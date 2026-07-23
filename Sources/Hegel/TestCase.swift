import CHegel

enum TestControl: Error {
    case invalid
    case overrun
}

enum TestStatus {
    case valid
    case invalid
    case overrun
    case interesting(String)
}

/// One linear test case supplied by Hegel.
///
/// A test case can be borrowed for any number of draws. The runner consumes it
/// exactly once when the property finishes.
@safe
public struct TestCase: ~Copyable {
    var context: Context
    var handle: OpaquePointer

    init(handle: OpaquePointer) throws {
        self.context = try Context()
        unsafe self.handle = handle
    }

    deinit {
        _ = unsafe hegel_test_case_free(context.handle, handle)
    }

    /// Draws a value from a generator.
    public func draw<Value>(_ generator: Generator<Value>) throws -> Value {
        try generator.draw(self)
    }

    /// Rejects the current draw when a property precondition is false.
    public func assume(_ condition: @autoclosure () -> Bool) throws {
        guard condition() else {
            throw TestControl.invalid
        }
    }

    consuming func complete(_ status: TestStatus) throws {
        let result: hegel_result_t
        switch status {
        case .valid:
            result = unsafe hegel_mark_complete(
                context.handle,
                handle,
                UInt32(HEGEL_STATUS_VALID.rawValue),
                nil,
            )
        case .invalid:
            result = unsafe hegel_mark_complete(
                context.handle,
                handle,
                UInt32(HEGEL_STATUS_INVALID.rawValue),
                nil,
            )
        case .overrun:
            result = unsafe hegel_mark_complete(
                context.handle,
                handle,
                UInt32(HEGEL_STATUS_OVERRUN.rawValue),
                nil,
            )
        case .interesting(let origin):
            result = origin.withCString { origin in
                unsafe hegel_mark_complete(
                    context.handle,
                    handle,
                    UInt32(HEGEL_STATUS_INTERESTING.rawValue),
                    origin,
                )
            }
        }
        try context.check(result)
    }

    func integer<Integer: FixedWidthInteger>(
        in range: ClosedRange<Integer>
    ) throws -> Integer {
        let minimum = integerBytes(range.lowerBound)
        let maximum = integerBytes(range.upperBound)
        var output = Array(repeating: UInt8(0), count: max(minimum.count, maximum.count))
        var outputLength = 0
        let result = minimum.withUnsafeBufferPointer { minimum in
            maximum.withUnsafeBufferPointer { maximum in
                output.withUnsafeMutableBufferPointer { output in
                    unsafe hegel_generate_integer_big(
                        context.handle,
                        handle,
                        minimum.baseAddress,
                        minimum.count,
                        maximum.baseAddress,
                        maximum.count,
                        output.baseAddress,
                        output.count,
                        &outputLength,
                    )
                }
            }
        }
        try checkDraw(result)
        var value: Integer = 0
        for (index, byte) in output.prefix(Integer.bitWidth / 8).enumerated() {
            value |= Integer(truncatingIfNeeded: byte) << (index * 8)
        }
        return value
    }

    func boolean(probability: Double) throws -> Bool {
        var value = false
        let result = unsafe hegel_generate_boolean(
            context.handle,
            handle,
            probability,
            false,
            false,
            &value,
        )
        try checkDraw(result)
        return value
    }

    func float(
        in range: ClosedRange<Float>?,
        allowingNaN: Bool,
        allowingInfinity: Bool,
        allowingSubnormal: Bool,
    ) throws -> Float {
        var value = 0.0
        let result = unsafe hegel_generate_float(
            context.handle,
            handle,
            32,
            Double(range?.lowerBound ?? -.infinity),
            Double(range?.upperBound ?? .infinity),
            allowingNaN,
            allowingInfinity,
            false,
            false,
            Double(allowingSubnormal ? Float.leastNonzeroMagnitude : Float.leastNormalMagnitude),
            &value,
        )
        try checkDraw(result)
        return Float(value)
    }

    func float(
        in range: ClosedRange<Double>?,
        allowingNaN: Bool,
        allowingInfinity: Bool,
        allowingSubnormal: Bool,
    ) throws -> Double {
        var value = 0.0
        let result = unsafe hegel_generate_float(
            context.handle,
            handle,
            64,
            range?.lowerBound ?? -.infinity,
            range?.upperBound ?? .infinity,
            allowingNaN,
            allowingInfinity,
            false,
            false,
            allowingSubnormal ? Double.leastNonzeroMagnitude : Double.leastNormalMagnitude,
            &value,
        )
        try checkDraw(result)
        return value
    }

    func bytes(size: ClosedRange<Int>) throws -> [UInt8] {
        var output = unsafe hegel_generate_bytes_result_t(data: nil, len: 0)
        try checkDraw(
            unsafe hegel_generate_bytes(
                context.handle,
                handle,
                UInt64(size.lowerBound),
                UInt64(size.upperBound),
                &output,
            )
        )
        defer {
            _ = unsafe hegel_generate_bytes_result_free(context.handle, &output)
        }
        return unsafe Array(
            UnsafeBufferPointer(start: output.data, count: output.len)
        )
    }

    func string(using generator: StringGeneratorHandle) throws -> String {
        var output = unsafe hegel_generate_string_result_t(data: nil, len: 0)
        try checkDraw(
            unsafe hegel_generate_string(
                context.handle,
                handle,
                generator.handle,
                &output,
            )
        )
        defer {
            _ = unsafe hegel_generate_string_result_free(context.handle, &output)
        }
        let bytes = unsafe UnsafeRawBufferPointer(
            start: output.data,
            count: output.len
        ).bindMemory(to: UInt8.self)
        return unsafe String(decoding: bytes, as: UTF8.self)
    }

    func filtered<Value>(
        _ generator: Generator<Value>,
        by predicate: (Value) throws -> Bool,
    ) throws -> Value {
        for _ in 0..<3 {
            try checkDraw(
                unsafe hegel_start_span(
                    context.handle,
                    handle,
                    UInt64(HEGEL_LABEL_FILTER.rawValue),
                )
            )
            let value: Value
            let accepted: Bool
            do {
                value = try generator.draw(self)
                accepted = try predicate(value)
            } catch {
                _ = unsafe hegel_stop_span(context.handle, handle, false)
                throw error
            }
            guard accepted else {
                try checkDraw(
                    unsafe hegel_stop_span(context.handle, handle, true)
                )
                continue
            }
            try checkDraw(
                unsafe hegel_stop_span(context.handle, handle, false)
            )
            return value
        }
        throw TestControl.invalid
    }

    func array<Element>(
        of element: Generator<Element>,
        size: ClosedRange<Int>,
    ) throws -> [Element] {
        try withCollection(
            label: UInt64(HEGEL_LABEL_LIST.rawValue),
            size: size
        ) { collectionID in
            var elements: [Element] = []
            while try collectionHasMore(collectionID) {
                let value = try withSpan(
                    label: UInt64(HEGEL_LABEL_LIST_ELEMENT.rawValue)
                ) {
                    try element.draw(self)
                }
                elements.append(value)
            }
            return elements
        }
    }

    func set<Element>(
        of element: Generator<Element>,
        size: ClosedRange<Int>,
    ) throws -> Set<Element> {
        let domain = element.enumeratedValues.map(unique)
        let size = try collectionSize(size, limitedTo: domain?.count)
        return try withCollection(
            label: UInt64(HEGEL_LABEL_SET.rawValue),
            size: size
        ) { collectionID in
            var values: Set<Element> = []
            var available = domain
            while try collectionHasMore(collectionID) {
                let candidate = try withSpan(
                    label: UInt64(HEGEL_LABEL_SET_ELEMENT.rawValue)
                ) {
                    if let count = available?.count {
                        let index = try integer(in: 0...(count - 1))
                        return available!.remove(at: index)
                    }
                    return try element.draw(self)
                }
                guard values.insert(candidate).inserted else {
                    try reject(collectionID)
                    continue
                }
            }
            return values
        }
    }

    func dictionary<Key, Value>(
        keys: Generator<Key>,
        values: Generator<Value>,
        size: ClosedRange<Int>,
    ) throws -> [Key: Value] {
        let domain = keys.enumeratedValues.map(unique)
        let size = try collectionSize(size, limitedTo: domain?.count)
        return try withCollection(
            label: UInt64(HEGEL_LABEL_MAP.rawValue),
            size: size
        ) { collectionID in
            var dictionary: [Key: Value] = [:]
            var available = domain
            while try collectionHasMore(collectionID) {
                try checkDraw(
                    unsafe hegel_start_span(
                        context.handle,
                        handle,
                        UInt64(HEGEL_LABEL_MAP_ENTRY.rawValue),
                    )
                )
                let key: Key
                do {
                    if let count = available?.count {
                        let index = try integer(in: 0...(count - 1))
                        key = available!.remove(at: index)
                    } else {
                        key = try keys.draw(self)
                    }
                } catch {
                    _ = unsafe hegel_stop_span(context.handle, handle, false)
                    throw error
                }
                guard dictionary.index(forKey: key) == nil else {
                    do {
                        try reject(collectionID)
                    } catch {
                        _ = unsafe hegel_stop_span(context.handle, handle, false)
                        throw error
                    }
                    try checkDraw(
                        unsafe hegel_stop_span(context.handle, handle, true)
                    )
                    continue
                }
                do {
                    dictionary[key] = try values.draw(self)
                } catch {
                    _ = unsafe hegel_stop_span(context.handle, handle, false)
                    throw error
                }
                try checkDraw(
                    unsafe hegel_stop_span(context.handle, handle, false)
                )
            }
            return dictionary
        }
    }

    func withSpan<Result>(
        label: UInt64,
        _ body: () throws -> Result,
    ) throws -> Result {
        try checkDraw(
            unsafe hegel_start_span(context.handle, handle, label)
        )
        let result: Result
        do {
            result = try body()
        } catch {
            _ = unsafe hegel_stop_span(context.handle, handle, false)
            throw error
        }
        try checkDraw(
            unsafe hegel_stop_span(context.handle, handle, false)
        )
        return result
    }

    func checkDraw(_ result: hegel_result_t) throws {
        switch result {
        case HEGEL_OK:
            return
        case HEGEL_E_STOP_TEST:
            throw TestControl.overrun
        case HEGEL_E_ASSUME:
            throw TestControl.invalid
        default:
            throw context.error(for: result)
        }
    }

    private func withCollection<Result>(
        label: UInt64,
        size: ClosedRange<Int>,
        _ body: (Int64) throws -> Result,
    ) throws -> Result {
        try withSpan(label: label) {
            var collectionID: Int64 = 0
            try checkDraw(
                unsafe hegel_new_collection(
                    context.handle,
                    handle,
                    UInt64(size.lowerBound),
                    UInt64(size.upperBound),
                    &collectionID,
                )
            )
            return try body(collectionID)
        }
    }

    private func collectionHasMore(_ collectionID: Int64) throws -> Bool {
        var more = false
        try checkDraw(
            unsafe hegel_collection_more(
                context.handle,
                handle,
                collectionID,
                &more,
            )
        )
        return more
    }

    private func reject(_ collectionID: Int64) throws {
        try checkDraw(
            unsafe hegel_collection_reject(
                context.handle,
                handle,
                collectionID,
                nil,
            )
        )
    }
}

private func integerBytes<Integer: FixedWidthInteger>(_ value: Integer) -> [UInt8] {
    precondition(Integer.bitWidth.isMultiple(of: 8))
    var remaining = value
    var bytes: [UInt8] = []
    for _ in 0..<(Integer.bitWidth / 8) {
        bytes.append(UInt8(truncatingIfNeeded: remaining))
        remaining >>= 8
    }
    if !Integer.isSigned {
        bytes.append(0)
    }
    return bytes
}

private func unique<Value: Hashable>(_ values: [Value]) -> [Value] {
    var seen: Set<Value> = []
    return values.filter { seen.insert($0).inserted }
}

private func collectionSize(
    _ size: ClosedRange<Int>,
    limitedTo limit: Int?
) throws -> ClosedRange<Int> {
    guard let limit else {
        return size
    }
    guard size.lowerBound <= limit else {
        throw TestControl.invalid
    }
    return size.lowerBound...min(size.upperBound, limit)
}
