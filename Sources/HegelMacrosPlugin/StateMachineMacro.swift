#if HegelMacros
public import SwiftSyntax
import SwiftSyntaxBuilder
public import SwiftSyntaxMacros

public struct StateMachineMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext,
    ) throws -> [DeclSyntax] {
        guard let declaration = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(
                node,
                "@StateMachine can only be attached to a struct",
                id: "state-machine-requires-struct",
            )
            return []
        }

        var rules: [FunctionDeclSyntax] = []
        var invariants: [FunctionDeclSyntax] = []
        for member in declaration.memberBlock.members {
            guard let function = member.decl.as(FunctionDeclSyntax.self) else {
                continue
            }

            let isRule = function.hasAttribute(named: "Rule")
            let isInvariant = function.hasAttribute(named: "Invariant")
            guard isRule != isInvariant else {
                continue
            }

            if isRule, FunctionValidator.isValid(function, as: .rule) {
                rules.append(function)
            }
            if isInvariant, FunctionValidator.isValid(function, as: .invariant) {
                invariants.append(function)
            }
        }

        guard !rules.isEmpty else {
            context.diagnose(
                node,
                "@StateMachine requires at least one @Rule method",
                id: "state-machine-requires-rule",
            )
            return []
        }

        diagnoseDuplicateNames(in: rules, role: .rule, context: context)
        diagnoseDuplicateNames(in: invariants, role: .invariant, context: context)

        let access = declaration.generatedMemberAccess
        return [
            descriptorProperty(
                named: "rules",
                descriptor: "Rule",
                functions: rules,
                access: access,
            ),
            descriptorProperty(
                named: "invariants",
                descriptor: "Invariant",
                functions: invariants,
                access: access,
            ),
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext,
    ) throws -> [ExtensionDeclSyntax] {
        guard let declaration = declaration.as(StructDeclSyntax.self) else {
            return []
        }
        let hasRule = declaration.memberBlock.members.contains { member in
            guard let function = member.decl.as(FunctionDeclSyntax.self) else {
                return false
            }
            return function.hasAttribute(named: "Rule")
                && !function.hasAttribute(named: "Invariant")
                && FunctionValidator.isValid(function, as: .rule)
        }
        guard hasRule else {
            return []
        }
        return [
            try ExtensionDeclSyntax(
                "extension \(type.trimmed): Hegel.StateMachine {}"
            )
        ]
    }

    private static func descriptorProperty(
        named propertyName: String,
        descriptor: String,
        functions: [FunctionDeclSyntax],
        access: String,
    ) -> DeclSyntax {
        guard !functions.isEmpty else {
            return """
                \(raw: access)static var \(raw: propertyName): [Hegel.\(raw: descriptor)<Self>] {
                    []
                }
                """
        }

        let elements = ArrayElementListSyntax(
            functions.map { function in
                ArrayElementSyntax(
                    expression: descriptorExpression(
                        for: function,
                        descriptor: descriptor,
                    ).with(\.leadingTrivia, .newline),
                    trailingComma: .commaToken(),
                )
            }
        )
        let descriptors = ArrayExprSyntax(
            elements: elements,
            rightSquare: .rightSquareToken(
                leadingTrivia: .newline
            ),
        )
        return """
            \(raw: access)static var \(raw: propertyName): [Hegel.\(raw: descriptor)<Self>] {
                \(descriptors)
            }
            """
    }

    private static func descriptorExpression(
        for function: FunctionDeclSyntax,
        descriptor: String,
    ) -> ExprSyntax {
        let name = StringLiteralExprSyntax(content: function.name.text)
        let invocation = invocation(of: function)
        return """
            Hegel.\(raw: descriptor)(\(name)) { machine, tc in
                \(invocation)
            }
            """
    }

    private static func invocation(
        of function: FunctionDeclSyntax
    ) -> ExprSyntax {
        var effects: [String] = []
        if function.signature.effectSpecifiers?.throwsClause != nil {
            effects.append("try")
        }
        if function.signature.effectSpecifiers?.asyncSpecifier != nil {
            effects.append("await")
        }

        let parameter = function.signature.parameterClause.parameters.first
        let arguments: String
        if let parameter {
            if parameter.firstName.tokenKind == .wildcard {
                arguments = "tc"
            } else {
                arguments = "\(parameter.firstName.text): tc"
            }
        } else {
            arguments = ""
        }

        let prefix = effects.isEmpty ? "" : effects.joined(separator: " ") + " "
        return "\(raw: prefix)machine.\(function.name.trimmed)(\(raw: arguments))"
    }

    private static func diagnoseDuplicateNames(
        in functions: [FunctionDeclSyntax],
        role: FunctionRole,
        context: some MacroExpansionContext,
    ) {
        var names: Set<String> = []
        for function in functions where !names.insert(function.name.text).inserted {
            context.diagnose(
                function.name,
                "@\(role.attributeName) method names must be unique",
                id: "duplicate-\(role.diagnosticName)-name",
            )
        }
    }
}

extension StructDeclSyntax {
    fileprivate var generatedMemberAccess: String {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.package):
                return "package "
            case .keyword(.public):
                return "public "
            default:
                continue
            }
        }
        return ""
    }
}
#endif
