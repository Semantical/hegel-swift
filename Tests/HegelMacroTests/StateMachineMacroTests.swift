#if HegelMacros
import HegelMacrosPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite
struct StateMachineMacroTests {
    private var macroSpecs: [String: MacroSpec] {
        [
            "Invariant": MacroSpec(type: InvariantMacro.self),
            "Rule": MacroSpec(type: RuleMacro.self),
            "StateMachine": MacroSpec(type: StateMachineMacro.self),
        ]
    }

    @Test
    func expansion() {
        assertMacroExpansion(
            """
            @StateMachine
            struct PoolMachine {
                @Rule
                mutating func add(tc: borrowing TestCase) throws {}

                @Rule
                mutating func reset() async {}

                @Invariant
                func `has expected contents`(_ tc: borrowing Hegel.TestCase) async throws {}
            }
            """,
            expandedSource: """
                struct PoolMachine {
                    mutating func add(tc: borrowing TestCase) throws {}
                    mutating func reset() async {}
                    func `has expected contents`(_ tc: borrowing Hegel.TestCase) async throws {}

                    static var rules: [Hegel.Rule<Self>] {
                        [
                        Hegel.Rule("add") { machine, tc in
                            try machine.add(tc: tc)
                        },
                        Hegel.Rule("reset") { machine, tc in
                            await machine.reset()
                        },
                        ]
                    }

                    static var invariants: [Hegel.Invariant<Self>] {
                        [
                        Hegel.Invariant("`has expected contents`") { machine, tc in
                            try await machine.`has expected contents`(tc)
                        },
                        ]
                    }
                }

                extension PoolMachine: Hegel.StateMachine {
                }
                """,
            macroSpecs: macroSpecs,
            indentationWidth: .spaces(4),
            failureHandler: recordFailure,
        )
    }

    @Test
    func `mutating invariant diagnostic`() {
        assertMacroExpansion(
            """
            @StateMachine
            struct Machine {
                @Rule
                mutating func step() {}

                @Invariant
                mutating func check() {}
            }
            """,
            expandedSource: """
                struct Machine {
                    mutating func step() {}
                    mutating func check() {}

                    static var rules: [Hegel.Rule<Self>] {
                        [
                        Hegel.Rule("step") { machine, tc in
                            machine.step()
                        },
                        ]
                    }

                    static var invariants: [Hegel.Invariant<Self>] {
                        []
                    }
                }

                extension Machine: Hegel.StateMachine {
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Invariant methods cannot mutate the state machine",
                    line: 7,
                    column: 5,
                    severity: .error,
                )
            ],
            macroSpecs: macroSpecs,
            indentationWidth: .spaces(4),
            failureHandler: recordFailure,
        )
    }

    @Test
    func `borrowing parameter diagnostic`() {
        assertMacroExpansion(
            """
            @StateMachine
            struct Machine {
                @Rule
                mutating func step(testCase: TestCase) {}
            }
            """,
            expandedSource: """
                struct Machine {
                    mutating func step(testCase: TestCase) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Rule's parameter must have type borrowing TestCase",
                    line: 4,
                    column: 34,
                    severity: .error,
                ),
                DiagnosticSpec(
                    message: "@StateMachine requires at least one @Rule method",
                    line: 1,
                    column: 1,
                    severity: .error,
                ),
            ],
            macroSpecs: macroSpecs,
            indentationWidth: .spaces(4),
            failureHandler: recordFailure,
        )
    }

    @Test
    func `TestCase parameter diagnostic`() {
        assertMacroExpansion(
            """
            @StateMachine
            struct Machine {
                @Rule
                mutating func step(testCase: borrowing Int) {}
            }
            """,
            expandedSource: """
                struct Machine {
                    mutating func step(testCase: borrowing Int) {}
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Rule's parameter must have type borrowing TestCase",
                    line: 4,
                    column: 34,
                    severity: .error,
                ),
                DiagnosticSpec(
                    message: "@StateMachine requires at least one @Rule method",
                    line: 1,
                    column: 1,
                    severity: .error,
                ),
            ],
            macroSpecs: macroSpecs,
            indentationWidth: .spaces(4),
            failureHandler: recordFailure,
        )
    }

    @Test
    func `declaration diagnostics`() {
        assertMacroExpansion(
            """
            @StateMachine
            final class Machine {}

            struct Other {
                @Rule
                var value = 0
            }
            """,
            expandedSource: """
                final class Machine {}

                struct Other {
                    var value = 0
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@StateMachine can only be attached to a struct",
                    line: 1,
                    column: 1,
                    severity: .error,
                ),
                DiagnosticSpec(
                    message: "@Rule can only be attached to an instance method",
                    line: 5,
                    column: 5,
                    severity: .error,
                ),
            ],
            macroSpecs: macroSpecs,
            indentationWidth: .spaces(4),
            failureHandler: recordFailure,
        )
    }
}

private func recordFailure(_ failure: TestFailureSpec) {
    Issue.record(
        Comment(rawValue: failure.message),
        sourceLocation: SourceLocation(
            fileID: failure.location.fileID,
            filePath: failure.location.filePath,
            line: failure.location.line,
            column: failure.location.column,
        ),
    )
}
#endif
