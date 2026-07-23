import CHegel

@safe
struct Context: ~Copyable {
    var handle: OpaquePointer

    init() throws(HegelError) {
        guard let handle = unsafe hegel_context_new() else {
            throw HegelError("Hegel could not allocate an error context.")
        }
        unsafe self.handle = handle
    }

    deinit {
        _ = unsafe hegel_context_free(handle)
    }

    func error(for result: hegel_result_t) -> HegelError {
        let message = unsafe hegel_context_last_error(handle).map(String.init(cString:))
        return HegelError(
            message.map { "Hegel error \(result.rawValue): \($0)" }
                ?? "Hegel error \(result.rawValue)."
        )
    }

    func check(_ result: hegel_result_t) throws(HegelError) {
        guard result == HEGEL_OK else {
            throw error(for: result)
        }
    }
}
