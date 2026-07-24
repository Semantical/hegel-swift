#if HegelMacros
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct HegelMacroDiagnostic: DiagnosticMessage {
    var message: String
    var diagnosticID: MessageID
    var severity: DiagnosticSeverity {
        .error
    }

    init(
        _ message: String,
        id: String,
    ) {
        self.message = message
        self.diagnosticID = MessageID(
            domain: "HegelMacros",
            id: id,
        )
    }
}

extension MacroExpansionContext {
    func diagnose(
        _ node: some SyntaxProtocol,
        _ message: String,
        id: String,
    ) {
        diagnose(
            Diagnostic(
                node: Syntax(node),
                message: HegelMacroDiagnostic(message, id: id),
            )
        )
    }
}
#endif
