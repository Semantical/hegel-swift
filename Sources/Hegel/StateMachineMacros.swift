#if HegelMacros
/// Derives Hegel state-machine descriptors from methods marked with `@Rule`
/// and `@Invariant`.
@attached(member, names: named(rules), named(invariants))
@attached(extension, conformances: StateMachine)
public macro StateMachine() =
    #externalMacro(module: "HegelMacrosPlugin", type: "StateMachineMacro")

/// Marks a state-machine transition.
@attached(peer)
public macro Rule() =
    #externalMacro(module: "HegelMacrosPlugin", type: "RuleMacro")

/// Marks a property checked initially, finally, and at Hegel-selected join points.
/// Set `alwaysCheck` to check after every rule instead of sampling.
@attached(peer)
public macro Invariant(alwaysCheck: Bool = false) =
    #externalMacro(module: "HegelMacrosPlugin", type: "InvariantMacro")
#endif
