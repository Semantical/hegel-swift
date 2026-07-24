#if HegelMacros
import HegelMacrosPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import SwiftSyntaxMacrosTestSupport
import Testing

@Suite
struct StateMachineMacroTests {
    private var macros: [String: any Macro.Type] {
        [
            "Invariant": InvariantMacro.self,
            "Rule": RuleMacro.self,
            "StateMachine": StateMachineMacro.self,
        ]
    }

    @Test
    func expansion() {
        assertMacroExpansion(
            """
            @StateMachine
            struct PoolMachine {
                @Rule
                mutating func add(ctx: borrowing TestCase) throws {}

                @Rule
                mutating func reset() async {}

                @Invariant
                func hasExpectedContents(_ ctx: borrowing Hegel.TestCase) async throws {}
            }
            """,
            expandedSource: """
                struct PoolMachine {
                    mutating func add(ctx: borrowing TestCase) throws {}
                    mutating func reset() async {}
                    func hasExpectedContents(_ ctx: borrowing Hegel.TestCase) async throws {}

                    static var rules: [Hegel.Rule<Self>] {
                        [
                        Hegel.Rule("add") { machine, ctx in
                            try machine.add(ctx: ctx)
                        },
                        Hegel.Rule("reset") { machine, ctx in
                            await machine.reset()
                        },
                        ]
                    }

                    static var invariants: [Hegel.Invariant<Self>] {
                        [
                        Hegel.Invariant("hasExpectedContents") { machine, ctx in
                            try await machine.hasExpectedContents(ctx)
                        },
                        ]
                    }
                }

                extension PoolMachine: Hegel.StateMachine {
                }
                """,
            macros: macros,
            indentationWidth: .spaces(4),
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
                        Hegel.Rule("step") { machine, ctx in
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
            macros: macros,
            indentationWidth: .spaces(4),
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
            macros: macros,
            indentationWidth: .spaces(4),
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
            macros: macros,
            indentationWidth: .spaces(4),
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
            macros: macros,
            indentationWidth: .spaces(4),
        )
    }
}
#endif
