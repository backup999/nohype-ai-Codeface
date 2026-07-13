/// One node in the **filtered, role-tagged** program tree used for hierarchy and deps.
///
/// Not the full CST: noise (`{`, operators as pure syntax, `pass`, …) is dropped.
/// `kind` stays language-native (Tree-sitter node type string). Optional grammar
/// fields land in `attributes` free-form (e.g. Swift `declaration_kind` → `"struct"`).
struct CodeNode: Equatable, Sendable {
    var role: Role
    /// Tree-sitter node type, e.g. `class_declaration`, `call_expression`.
    var kind: String
    /// Best-effort surface name (identifier, operator-ish text, import path, …).
    var name: String
    /// Selected grammar fields keyed by Tree-sitter field name.
    var attributes: [String: String]
    var children: [CodeNode]

    init(
        role: Role,
        kind: String,
        name: String,
        attributes: [String: String] = [:],
        children: [CodeNode] = []
    ) {
        self.role = role
        self.kind = kind
        self.name = name
        self.attributes = attributes
        self.children = children
    }
    
    /// Analysis role assigned when projecting the CST into a `ProgramNode`.
    ///
    /// Tree-sitter has no declaration/reference notion; this is **our** early tag so
    /// dependency algorithms need not re-classify every `kind` on every pass.
    /// Overload resolution (matching args/operand types to a specific overload) is a
    /// **later** linking step — `role` only separates "this names a binding" from
    /// "this uses a name".
    enum Role: String, Equatable, Sendable {
        /// Introduces a named binding / structural unit (type, function, property, …).
        case declaration
        /// Uses a name (call, type mention, inheritance/base, import, …).
        case reference
    }
}
