/// Display-oriented helpers for free-string symbol kinds.
///
/// Architecture stores lightweight labels only (not a closed ontology). TreeSitter
/// grammar node types are humanized here; refined tokens (e.g. Swift
/// `declaration_kind`) should be preferred by adapters before falling back.
enum SymbolKindDisplay
{
    /// Prefer a refined attribute token; else humanize a grammar node type id.
    ///
    /// - Parameters:
    ///   - nodeKind: Tree-sitter (or similar) node type, e.g. `function_declaration`.
    ///   - refinedKind: Optional short token, e.g. Swift `declaration_kind` → `struct`.
    static func kindName(nodeKind: String, refinedKind: String? = nil) -> String
    {
        if let refinedKind, !refinedKind.isEmpty
        {
            return titleCaseToken(refinedKind)
        }
        return humanize(nodeKind)
    }
    
    /// Language-agnostic humanization of snake_case grammar kinds.
    ///
    /// Examples: `function_declaration` → `Function`, `class_definition` → `Class`.
    static func humanize(_ rawKind: String) -> String
    {
        let noise: Set<String> = [
            "declaration", "definition", "expression", "statement", "specifier"
        ]
        
        let parts = rawKind
            .split(separator: "_")
            .map(String.init)
            .filter { !noise.contains($0.lowercased()) }
        
        let words = parts.isEmpty
            ? rawKind.split(separator: "_").map(String.init)
            : parts
        
        let titled = words.map(titleCaseToken)
        let joined = titled.joined(separator: " ")
        return joined.isEmpty ? "Unknown Kind of Symbol" : joined
    }
    
    private static func titleCaseToken(_ token: String) -> String
    {
        guard let first = token.first else { return token }
        return first.uppercased() + token.dropFirst().lowercased()
    }
}
