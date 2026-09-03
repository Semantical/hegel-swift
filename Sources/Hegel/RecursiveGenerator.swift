import CHegel

extension Gen {
    /// Generates recursively defined values from distinct leaf and branch cases.
    ///
    /// Hegel chooses whether each subvalue is a leaf or a branch. Branches nest
    /// at most `maxDepth` levels, and an attempt that exceeds `maxLeaves` leaf
    /// values is discarded and retried with a smaller target.
    public static func recursive(
        maxDepth: Int = 32,
        maxLeaves: Int = 100,
        branch: @escaping (Self) -> Self,
        leaf: () -> Self,
    ) -> Self {
        precondition(maxDepth >= 0)
        precondition(maxLeaves >= 0)

        let definition = RecursiveGeneratorDefinition(
            leaf: leaf(),
            branch: branch,
        )
        return .unspanned { testCase in
            let recursion = try testCase.recursion(
                maxDepth: maxDepth,
                maxLeaves: maxLeaves,
            )
            while true {
                do {
                    return
                        try definition
                        .subtree(recursion: recursion, depth: 0)
                        .draw(testCase)
                } catch RecursionControl.leafBudgetExceeded {
                    try testCase.retry(recursion)
                } catch RecursionControl.mispriced {
                    continue
                }
            }
        }
    }
}

private final class RecursiveGeneratorDefinition<Value> {
    var leaf: Gen<Value>
    var branch: (Gen<Value>) -> Gen<Value>

    init(
        leaf: Gen<Value>,
        branch: @escaping (Gen<Value>) -> Gen<Value>,
    ) {
        self.leaf = leaf
        self.branch = branch
    }

    func subtree(
        recursion: RecursionHandle,
        depth: UInt64,
    ) -> Gen<Value> {
        .unspanned { [self, recursion] testCase in
            try testCase.withRecursiveSpan {
                let value: Value
                if try testCase.shouldBranch(recursion, depth: depth) {
                    value = try branch(
                        subtree(recursion: recursion, depth: depth + 1)
                    ).draw(testCase)
                } else {
                    try testCase.countLeaf(recursion)
                    value = try leaf.draw(testCase)
                }

                guard depth == 0 else {
                    return value
                }
                try testCase.finish(recursion)
                return value
            }
        }
    }
}

private enum RecursionControl: Error {
    case leafBudgetExceeded
    case mispriced
}

@safe
private final class RecursionHandle {
    var rawValue: OpaquePointer

    init(_ rawValue: OpaquePointer) {
        unsafe self.rawValue = rawValue
    }

    deinit {
        _ = unsafe hegel_recursion_free(nil, rawValue)
    }
}

extension TestCase {
    fileprivate func recursion(
        maxDepth: Int,
        maxLeaves: Int,
    ) throws -> RecursionHandle {
        var recursion: OpaquePointer?
        try checkDraw(
            unsafe hegel_new_recursion(
                context.handle,
                handle,
                UInt64(maxDepth),
                UInt64(maxLeaves),
                &recursion,
            )
        )
        guard let recursion = unsafe recursion else {
            throw HegelError("Hegel returned an empty recursion handle.")
        }
        return unsafe RecursionHandle(recursion)
    }

    fileprivate func shouldBranch(
        _ recursion: RecursionHandle,
        depth: UInt64,
    ) throws -> Bool {
        var branch = false
        try checkDraw(
            unsafe hegel_recursion_branch(
                context.handle,
                handle,
                recursion.rawValue,
                depth,
                &branch,
            )
        )
        return branch
    }

    fileprivate func countLeaf(_ recursion: RecursionHandle) throws {
        let result = unsafe hegel_recursion_leaf(
            context.handle,
            handle,
            recursion.rawValue,
        )
        guard result != HEGEL_E_RETRY else {
            throw RecursionControl.leafBudgetExceeded
        }
        try checkDraw(result)
    }

    fileprivate func retry(_ recursion: RecursionHandle) throws {
        try checkDraw(
            unsafe hegel_recursion_retry(
                context.handle,
                handle,
                recursion.rawValue,
            )
        )
    }

    fileprivate func finish(_ recursion: RecursionHandle) throws {
        let result = unsafe hegel_recursion_finish(
            context.handle,
            handle,
            recursion.rawValue,
        )
        guard result != HEGEL_E_RETRY else {
            throw RecursionControl.mispriced
        }
        try checkDraw(result)
    }

    fileprivate func withRecursiveSpan<Result>(
        _ body: () throws -> Result
    ) throws -> Result {
        try checkDraw(
            unsafe hegel_start_span(
                context.handle,
                handle,
                UInt64(HEGEL_LABEL_RECURSIVE.rawValue),
            )
        )
        do {
            let result = try body()
            try checkDraw(
                unsafe hegel_stop_span(context.handle, handle, false)
            )
            return result
        } catch let control as RecursionControl {
            // Hegel discards the open recursive spans as part of retrying.
            throw control
        } catch {
            _ = unsafe hegel_stop_span(context.handle, handle, false)
            throw error
        }
    }
}
