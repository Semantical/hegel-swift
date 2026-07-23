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
    public func draw<Value>(_ generator: borrowing Generator<Value>) throws -> Value {
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

    func integer(in range: ClosedRange<Int>) throws -> Int {
        var value: Int64 = 0
        let result = unsafe hegel_generate_integer(
            context.handle,
            handle,
            Int64(range.lowerBound),
            Int64(range.upperBound),
            &value,
        )
        try checkDraw(result)
        return Int(value)
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

    func array<Element>(
        of element: borrowing Generator<Element>,
        size: ClosedRange<Int>,
    ) throws -> [Element] {
        try withSpan(label: UInt64(HEGEL_LABEL_LIST.rawValue)) {
            var collectionID: Int64 = 0
            let result = unsafe hegel_new_collection(
                context.handle,
                handle,
                UInt64(size.lowerBound),
                UInt64(size.upperBound),
                &collectionID,
            )
            try checkDraw(result)

            var elements: [Element] = []
            while true {
                var more = false
                let result = unsafe hegel_collection_more(
                    context.handle,
                    handle,
                    collectionID,
                    &more,
                )
                try checkDraw(result)
                guard more else {
                    return elements
                }

                let value = try withSpan(
                    label: UInt64(HEGEL_LABEL_LIST_ELEMENT.rawValue)
                ) {
                    try element.draw(self)
                }
                elements.append(value)
            }
        }
    }

    func withSpan<Result>(
        label: UInt64,
        _ body: () throws -> Result,
    ) throws -> Result {
        try checkDraw(
            unsafe hegel_start_span(context.handle, handle, label)
        )
        do {
            let result = try body()
            try checkDraw(
                unsafe hegel_stop_span(context.handle, handle, false)
            )
            return result
        } catch {
            _ = unsafe hegel_stop_span(context.handle, handle, false)
            throw error
        }
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
}
