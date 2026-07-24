#if HegelMacros
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct HegelMacrosPlugin: CompilerPlugin {
    var providingMacros: [any Macro.Type] = [
        InvariantMacro.self,
        RuleMacro.self,
        StateMachineMacro.self,
    ]
}
#else
@main
enum HegelMacrosPluginUnavailable {
    static func main() {}
}
#endif
