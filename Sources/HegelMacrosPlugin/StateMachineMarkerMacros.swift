#if HegelMacros
public import SwiftSyntax
public import SwiftSyntaxMacros

public struct RuleMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        FunctionValidator.diagnose(
            declaration,
            attachedAt: node,
            as: .rule,
            context: context,
        )
        return []
    }
}

public struct InvariantMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        if declaration.as(FunctionDeclSyntax.self)?.hasAttribute(named: "Rule") == true {
            return []
        }
        FunctionValidator.diagnose(
            declaration,
            attachedAt: node,
            as: .invariant,
            context: context,
        )
        return []
    }
}

enum FunctionRole {
    case invariant
    case rule

    var attributeName: String {
        switch self {
        case .invariant:
            "Invariant"
        case .rule:
            "Rule"
        }
    }

    var diagnosticName: String {
        attributeName.lowercased()
    }
}

enum FunctionValidator {
    static func isValid(
        _ function: FunctionDeclSyntax,
        as role: FunctionRole,
    ) -> Bool {
        issues(for: function, as: role).isEmpty
            && !function.hasAttribute(named: role == .rule ? "Invariant" : "Rule")
    }

    static func diagnose(
        _ declaration: some DeclSyntaxProtocol,
        attachedAt node: AttributeSyntax,
        as role: FunctionRole,
        context: some MacroExpansionContext,
    ) {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            context.diagnose(
                node,
                "@\(role.attributeName) can only be attached to an instance method",
                id: "\(role.diagnosticName)-requires-method",
            )
            return
        }

        let otherRole: FunctionRole = role == .rule ? .invariant : .rule
        if function.hasAttribute(named: otherRole.attributeName) {
            context.diagnose(
                node,
                "a method cannot be both @Rule and @Invariant",
                id: "conflicting-state-machine-markers",
            )
            return
        }

        for issue in issues(for: function, as: role) {
            context.diagnose(
                issue.node,
                issue.message,
                id: issue.id,
            )
        }
    }

    private static func issues(
        for function: FunctionDeclSyntax,
        as role: FunctionRole,
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for modifier in function.modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.class), .keyword(.static):
                issues.append(
                    ValidationIssue(
                        node: Syntax(modifier),
                        message: "@\(role.attributeName) requires an instance method",
                        id: "\(role.diagnosticName)-requires-instance-method",
                    )
                )
            case .keyword(.consuming):
                issues.append(
                    ValidationIssue(
                        node: Syntax(modifier),
                        message: "@\(role.attributeName) methods cannot consume the state machine",
                        id: "\(role.diagnosticName)-cannot-consume",
                    )
                )
            case .keyword(.mutating) where role == .invariant:
                issues.append(
                    ValidationIssue(
                        node: Syntax(modifier),
                        message: "@Invariant methods cannot mutate the state machine",
                        id: "invariant-cannot-mutate",
                    )
                )
            default:
                continue
            }
        }

        if function.genericParameterClause != nil || function.genericWhereClause != nil {
            issues.append(
                ValidationIssue(
                    node: Syntax(function.name),
                    message: "@\(role.attributeName) methods cannot be generic",
                    id: "\(role.diagnosticName)-cannot-be-generic",
                )
            )
        }

        if function.signature.returnClause != nil {
            issues.append(
                ValidationIssue(
                    node: Syntax(function.signature.returnClause!),
                    message: "@\(role.attributeName) methods must omit their return type",
                    id: "\(role.diagnosticName)-cannot-return-value",
                )
            )
        }

        let parameters = function.signature.parameterClause.parameters
        if parameters.count > 1 {
            issues.append(
                ValidationIssue(
                    node: Syntax(function.signature.parameterClause),
                    message:
                        "@\(role.attributeName) accepts no parameters or one borrowing TestCase",
                    id: "\(role.diagnosticName)-invalid-parameters",
                )
            )
            return issues
        }

        if let parameter = parameters.first, !parameter.isBorrowingTestCase {
            issues.append(
                ValidationIssue(
                    node: Syntax(parameter.type),
                    message:
                        "@\(role.attributeName)'s parameter must have type borrowing TestCase",
                    id: "\(role.diagnosticName)-test-case-must-borrow",
                )
            )
        }
        return issues
    }
}

private struct ValidationIssue {
    var node: Syntax
    var message: String
    var id: String
}

extension FunctionDeclSyntax {
    func hasAttribute(named name: String) -> Bool {
        attributes.contains { element in
            guard case .attribute(let attribute) = element else {
                return false
            }
            return attribute.unqualifiedName == name
        }
    }
}

extension AttributeSyntax {
    fileprivate var unqualifiedName: String? {
        if let name = attributeName.as(IdentifierTypeSyntax.self) {
            return name.name.text
        }
        if let name = attributeName.as(MemberTypeSyntax.self) {
            return name.name.text
        }
        return nil
    }
}

extension FunctionParameterSyntax {
    fileprivate var isBorrowingTestCase: Bool {
        guard let type = type.as(AttributedTypeSyntax.self) else {
            return false
        }
        let isBorrowing = type.specifiers.contains { specifier in
            specifier.as(SimpleTypeSpecifierSyntax.self)?.specifier.tokenKind
                == .keyword(.borrowing)
        }
        guard isBorrowing else {
            return false
        }
        if let name = type.baseType.as(IdentifierTypeSyntax.self) {
            return name.name.text == "TestCase"
        }
        if let name = type.baseType.as(MemberTypeSyntax.self) {
            return name.name.text == "TestCase"
        }
        return false
    }
}
#endif
