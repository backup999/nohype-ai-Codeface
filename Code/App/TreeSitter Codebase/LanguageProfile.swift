import SwiftTreeSitter

/// Per-language **projection** of that language’s Tree-sitter CST into `CodeNode`s.
///
/// ## What a profile is for
/// Tree-sitter already produces a full hierarchical CST. A profile does **not**
/// invent that hierarchy. It answers language-specific questions the shared walk
/// (`CodeTreeGenerator`) cannot know:
///
/// 1. **Which node types are worth keeping** (deps-relevant decls/refs vs noise).
/// 2. **Role** of each kept type (`.declaration` vs `.reference`) — early for deps.
/// 3. **How to read a surface `name`** (field name, pattern dig, call callee, …).
/// 4. **Which optional grammar fields** to copy into `CodeNode.attributes`.
/// 5. **Where bare `identifier` nodes count as references** (see loose fields).
///
/// It is **not** a shared ontology of “Interface” / “AbstractClass” across languages.
/// `CodeNode.kind` remains the raw Tree-sitter type string.
///
/// ## Why `rules` and `looseIdentifierFields` both exist
///
/// - **`rules`**: include a node **because its type alone** means something
///   (`function_declaration`, `call_expression`, `user_type`, …).
///
/// - **`looseIdentifierFields`**: some grammars put important name uses as plain
///   `identifier` with **no** dedicated node type (e.g. Python `class Foo(Bar)`:
///   `Bar` is just `identifier` under field `superclasses`). Listing `identifier`
///   in `rules` globally would also capture every parameter, loop variable, and
///   local — useless noise. Instead we only promote `identifier` to a reference
///   while walking **named fields** of certain parents (e.g. bases, import names).
///
/// Swift usually does not need this: types use `user_type` / `inheritance_specifier`,
/// so `looseIdentifierFields` is empty for `Swift`.
struct LanguageProfile: Sendable {
    /// How a CST node type maps into one code-tree node.
    struct Rule: Sendable {
        /// Declaration vs reference (dependency dualism).
        var role: TreeSitterCodeSymbol.Role
        /// Where to get `CodeNode.name` for this node type.
        var name: NameSource
    }

    /// Per-node-type strategy for reading a display / match name from the CST.
    enum NameSource: Sendable {
        /// Text of a Tree-sitter field (or that field’s subtree text).
        case field(String)
        /// Entire node source span.
        case nodeText
        /// Swift `property_declaration`: dig through `pattern` → bound identifier.
        case swiftPropertyName
        /// Swift `user_type`: primary `type_identifier`.
        case swiftUserTypeName
        /// Swift `call_expression`: callee identifier or navigation expression.
        case swiftCallExpression
        /// Python `call`: `function` field (identifier or attribute tail).
        case pythonCall
    }

    /// Tree-sitter node type → include in the code tree with this rule.
    let rules: [String: Rule]

    /// Grammar field names whose text is copied into `CodeNode.attributes`
    /// when present (e.g. Swift `"declaration_kind"` → `"struct"` / `"class"`).
    let attributeFields: [String]

    /// Contextual bare-identifier references (see type comment on `LanguageProfile`).
    ///
    /// Key = parent CST node type already in the code tree.
    /// Value = Tree-sitter **field names** on that parent under which `identifier`
    /// children become `.reference` code nodes.
    ///
    /// Example: `["class_definition": ["superclasses"]]` for `class Foo(Bar)`.
    let looseIdentifierFields: [String: [String]]

    // MARK: Swift

    static let swift = LanguageProfile(
        rules: [
            // Declarations
            "class_declaration": Rule(role: .declaration, name: .field("name")),
            "function_declaration": Rule(role: .declaration, name: .field("name")),
            "protocol_declaration": Rule(role: .declaration, name: .field("name")),
            "property_declaration": Rule(role: .declaration, name: .swiftPropertyName),
            "init_declaration": Rule(role: .declaration, name: .nodeText),
            "typealias_declaration": Rule(role: .declaration, name: .field("name")),
            // References
            "inheritance_specifier": Rule(role: .reference, name: .field("inherits_from")),
            "call_expression": Rule(role: .reference, name: .swiftCallExpression),
            "user_type": Rule(role: .reference, name: .swiftUserTypeName),
            "import_declaration": Rule(role: .reference, name: .nodeText),
        ],
        attributeFields: ["declaration_kind"],
        looseIdentifierFields: [:]
    )

    // MARK: Python

    static let python = LanguageProfile(
        rules: [
            "class_definition": Rule(role: .declaration, name: .field("name")),
            "function_definition": Rule(role: .declaration, name: .field("name")),
            "call": Rule(role: .reference, name: .pythonCall),
            "import_statement": Rule(role: .reference, name: .field("name")),
            "import_from_statement": Rule(role: .reference, name: .field("module_name")),
            "type": Rule(role: .reference, name: .nodeText),
        ],
        attributeFields: [],
        looseIdentifierFields: [
            "class_definition": ["superclasses"],
            "import_statement": ["name"],
            "import_from_statement": ["name"],
        ]
    )

    // MARK: Name / attributes

    func name(for node: Node, rule: Rule) -> String? {
        switch rule.name {
        case .field(let fieldName):
            return node.child(byFieldName: fieldName)?.text
        case .nodeText:
            return node.text
        case .swiftPropertyName:
            return Self.swiftPropertyName(node)
        case .swiftUserTypeName:
            return Self.swiftUserTypeName(node)
        case .swiftCallExpression:
            return Self.swiftCallName(node)
        case .pythonCall:
            return Self.pythonCallName(node)
        }
    }

    func attributes(for node: Node) -> [String: String] {
        var result: [String: String] = [:]
        for field in attributeFields {
            if let text = node.child(byFieldName: field)?.text {
                result[field] = text
            }
        }
        return result
    }
    
    /// Narrower span for the surface name when the grammar exposes it; else `nil`.
    func selectionRange(for node: Node, rule: Rule) -> CodeRange? {
        switch rule.name {
        case .field(let fieldName):
            return node.child(byFieldName: fieldName).map { CodeRange($0.pointRange) }
        case .swiftPropertyName:
            guard let pattern = node.child(byFieldName: "name") else { return nil }
            if let bound = pattern.child(byFieldName: "bound_identifier") {
                return CodeRange(bound.pointRange)
            }
            if let id = Self.firstNamedDescendant(pattern, types: ["simple_identifier"]) {
                return CodeRange(id.pointRange)
            }
            return CodeRange(pattern.pointRange)
        case .swiftUserTypeName:
            if let id = Self.firstNamedDescendant(node, types: ["type_identifier"]) {
                return CodeRange(id.pointRange)
            }
            return nil
        case .nodeText, .swiftCallExpression, .pythonCall:
            return nil
        }
    }
    
    // MARK: Name helpers
    
    private static func swiftPropertyName(_ node: Node) -> String? {
        guard let pattern = node.child(byFieldName: "name") else { return nil }
        if let bound = pattern.child(byFieldName: "bound_identifier") {
            return bound.text
        }
        return firstNamedDescendant(pattern, types: ["simple_identifier"])?.text
            ?? pattern.text
    }
    
    private static func swiftUserTypeName(_ node: Node) -> String? {
        firstNamedDescendant(node, types: ["type_identifier"])?.text ?? node.text
    }

    private static func swiftCallName(_ call: Node) -> String? {
        for i in 0 ..< call.namedChildCount {
            guard let child = call.namedChild(at: i),
                  let type = child.nodeType
            else { continue }
            if type == "simple_identifier" || type == "navigation_expression" {
                return child.text
            }
        }
        return nil
    }

    private static func pythonCallName(_ call: Node) -> String? {
        guard let function = call.child(byFieldName: "function") else { return nil }
        if function.nodeType == "identifier" {
            return function.text
        }
        if function.nodeType == "attribute" {
            return function.child(byFieldName: "attribute")?.text
        }
        return function.text
    }

    private static func firstNamedDescendant(_ node: Node, types: Set<String>) -> Node? {
        if let t = node.nodeType, types.contains(t) { return node }
        for i in 0 ..< node.namedChildCount {
            guard let child = node.namedChild(at: i) else { continue }
            if let found = firstNamedDescendant(child, types: types) {
                return found
            }
        }
        return nil
    }
}
