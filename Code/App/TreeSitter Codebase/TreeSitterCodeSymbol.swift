/// One node in the **filtered, role-tagged** code tree used for hierarchy and deps.
///
/// Not the full CST: noise (`{`, operators as pure syntax, `pass`, …) is dropped.
/// `kind` stays language-native (Tree-sitter node type string). Optional grammar
/// fields land in `attributes` free-form (e.g. Swift `declaration_kind` → `"struct"`).
struct TreeSitterCodeSymbol: Sendable {
    var role: Role
    /// Tree-sitter node type, e.g. `class_declaration`, `call_expression`.
    var kind: String
    /// Best-effort surface name (identifier, operator-ish text, import path, …).
    var name: String
    /// Selected grammar fields keyed by Tree-sitter field name.
    var attributes: [String: String]
    /// Full span of the CST node (start inclusive; end from Tree-sitter, typically exclusive character).
    var range: CodeRange
    /// Best-effort name span; falls back to `range` when no narrower span is available.
    var selectionRange: CodeRange
    var children: [TreeSitterCodeSymbol]
    
    init(
        role: Role,
        kind: String,
        name: String,
        attributes: [String: String] = [:],
        range: CodeRange = .zero,
        selectionRange: CodeRange? = nil,
        children: [TreeSitterCodeSymbol] = [],
        references: [ReferenceLocation] = []
    ) {
        self.role = role
        self.kind = kind
        self.name = name
        self.attributes = attributes
        self.range = range
        self.selectionRange = selectionRange ?? range
        self.children = children
        self.references = references
    }
    
    /// Compare structure for tests that do not care about exact spans.
    func isStructurallyEqual(to other: TreeSitterCodeSymbol) -> Bool {
        role == other.role
            && kind == other.kind
            && name == other.name
            && attributes == other.attributes
            && children.count == other.children.count
            && zip(children, other.children).allSatisfy { $0.isStructurallyEqual(to: $1) }
    }
     
    /// Analysis role assigned when projecting the CST into a `CodeNode`.
    ///
    /// Tree-sitter has no declaration/reference notion; this is **our** early tag so
    /// dependency algorithms need not re-classify every `kind` on every pass.
    /// Overload resolution (matching args/operand types to a specific overload) is a
    /// **later** linking step — `role` only separates "this names a binding" from
    /// "this uses a name".
    enum Role: String, Sendable {
        /// Introduces a named binding / structural unit (type, function, property, …).
        case declaration
        /// Uses a name (call, type mention, inheritance/base, import, …).
        case reference
    }
    
    // references
    
    let references: [ReferenceLocation]?
    
    struct ReferenceLocation: Codable, Sendable
    {
        /// without root folder, like: `"SubfolderOfRoot/Deeper/Subfolders/myFile.swift"`
        let filePathRelativeToRoot: String
        
        let range: CodeRange
    }
}

extension CodeRange {
    static let zero = CodeRange(start: CodePosition(line: 0, character: 0),
                                end: CodePosition(line: 0, character: 0))
}
