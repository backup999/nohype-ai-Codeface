import SwiftTreeSitter

// MARK: - Extractor

/// Projects source text into a language-agnostic `ProgramNode` tree.
///
/// Pipeline: **grammar parse (full CST)** → **profile filter** → program tree.
/// The walk is shared; only `LanguageProfile` differs per language.
///
/// Design goals for dependency work later:
/// - Keep **declaration** and **reference** sites in **one** tree (not outline-only).
/// - Walk **every** CST child of a kept node so param types, bases, and body calls
///   are not cut off when a `body` field also exists.
/// - Do **not** keep pure syntax noise; selection is deliberate and profile-driven.
enum CodeTreeGenerator {
    /// Parse `source` with the language grammar and return top-level program nodes.
    static func generateTree(
        from code: String,
        language: SourceLanguage
    ) throws -> [CodeNode] {
        let parser = Parser()
        try parser.setLanguage(language.treeSitterLanguage)

        guard let tree = parser.parse(code),
              let root = tree.rootNode
        else {
            throw HierarchyError.parseFailed
        }

        return collect(from: root, profile: language.profile)
    }

    /// Depth-first CST walk.
    ///
    /// - If `profile.rules` has this node type **and** a name can be read → emit
    ///   one `ProgramNode` (role from the rule; `kind` = raw node type).
    /// - Else if `allowLooseIdentifierReferences` and this is a bare `identifier`
    ///   → emit a **reference** (see `LanguageProfile.looseIdentifierFields`).
    /// - Else → do not emit this CST node; still recurse into children (filter).
    private static func collect(
        from node: Node,
        profile: LanguageProfile,
        allowLooseIdentifierReferences: Bool = false
    ) -> [CodeNode] {
        if let type = node.nodeType,
           let rule = profile.rules[type],
           let name = profile.name(for: node, rule: rule)
        {
            // References are program-tree **leaves**: the CST often nests the same
            // traditional name again (e.g. inheritance_specifier → user_type → Bar).
            // Recursing would emit two refs for one source occurrence. Declarations
            // still open their full CST children (nested decls + body/header refs).
            let children: [CodeNode] =
                rule.role == .reference
                ? []
                : childrenForSelectedNode(node, type: type, profile: profile)
            return [
                CodeNode(
                    role: rule.role,
                    kind: type,
                    name: name,
                    attributes: profile.attributes(for: node),
                    children: children
                ),
            ]
        }

        if allowLooseIdentifierReferences,
           node.nodeType == "identifier",
           let name = node.text
        {
            return [CodeNode(role: .reference, kind: "identifier", name: name)]
        }

        var result: [CodeNode] = []
        node.enumerateChildren { child in
            result.append(
                contentsOf: collect(
                    from: child,
                    profile: profile,
                    allowLooseIdentifierReferences: allowLooseIdentifierReferences
                )
            )
        }
        return result
    }

    /// Children of an already-selected program node: full CST child list.
    ///
    /// For each child, if its Tree-sitter **field name** is listed under
    /// `profile.looseIdentifierFields[parentType]`, recursion allows bare
    /// `identifier` nodes to become references. All other fields keep that flag off.
    private static func childrenForSelectedNode(
        _ node: Node,
        type: String,
        profile: LanguageProfile
    ) -> [CodeNode] {
        let looseFields = Set(profile.looseIdentifierFields[type] ?? [])
        var children: [CodeNode] = []
        for i in 0 ..< node.childCount {
            guard let child = node.child(at: i) else { continue }
            let field = node.fieldNameForChild(at: i)
            let loose = field.map { looseFields.contains($0) } ?? false
            children.append(
                contentsOf: collect(
                    from: child,
                    profile: profile,
                    allowLooseIdentifierReferences: loose
                )
            )
        }
        return children
    }
}

enum HierarchyError: Error, Sendable {
    case parseFailed
}
