import CHegel

@safe
final class StringGeneratorHandle {
    var context: Context
    var handle: OpaquePointer

    private init(
        context: consuming Context,
        handle: OpaquePointer,
    ) {
        self.context = consume context
        unsafe self.handle = handle
    }

    deinit {
        _ = unsafe hegel_string_generator_free(context.handle, handle)
    }

    static func text(size: ClosedRange<Int>) throws(HegelError) -> StringGeneratorHandle {
        let context = try Context()
        var handle: OpaquePointer?
        try context.check(
            unsafe hegel_string_generator_text(
                context.handle,
                UInt64(size.lowerBound),
                UInt64(size.upperBound),
                nil,
                0,
                UInt32.max,
                nil,
                0,
                nil,
                0,
                nil,
                0,
                nil,
                0,
                &handle,
            )
        )
        guard let handle = unsafe handle else {
            throw HegelError("Hegel returned an empty string generator.")
        }
        return unsafe StringGeneratorHandle(
            context: consume context,
            handle: handle,
        )
    }
}
