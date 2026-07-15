/// Scope-stack name resolution (v0): refs → decls → used-by on declarations.
///
/// Pure: `TreeSitterFolder` → new forest with `references` filled on matched decls.
/// No types, overloads, or imports — exact name match, most-local scope wins.
///
/// ## Scopes
///
/// 1. **Root (cross-scope index):** every name-binding declaration that lives at
///    file scope or as a member of a type-like container (class / struct / enum /
///    protocol / extension body, including nested types). First registration wins;
///    a second distinct decl with the same name makes the name **ambiguous**.
/// 2. **File scopes:** each file’s top-level name-binding decls, last-wins. When
///    the root marks a name ambiguous (e.g. two files both declare `foo`), a
///    same-file use still resolves via this scope instead of being dropped.
/// 3. **Nested body scopes:** when entering a declaration, its child decls are
///    registered with last-wins shadowing so sibling order and locals still work.
///
/// Lookup walks the stack inward→outward, so a local, sibling, or same-file
/// top-level always beats the root index. Function/method bodies do **not**
/// publish their nested locals into the root index (they stay body-scoped only).
enum TreeSitterReferenceLinker {
    
    // MARK: - Public
    
    static func link(_ folder: TreeSitterFolder) -> TreeSitterFolder {
        var root = Scope(policy: .rootFirstWinsOrAmbiguous)
        registerDeclarations(in: folder, pathPrefix: "", into: &root)
        
        var usedBy = [DeclKey: [TreeSitterCodeSymbol.ReferenceLocation]]()
        var stack = [root]
        resolveFiles(in: folder, pathPrefix: "", stack: &stack, usedBy: &usedBy)
        
        return rebuild(folder, pathPrefix: "", usedBy: usedBy)
    }
    
    // MARK: - Decl identity
    
    /// Stable key for a declaration site (file + span). Used only during linking.
    struct DeclKey: Hashable {
        let filePathRelativeToRoot: String
        let range: CodeRange
    }
    
    // MARK: - Scope
    
    struct Scope {
        enum Policy {
            /// Cross-scope index: first registration wins; a second distinct decl
            /// with the same name makes the name unresolvable (ambiguous).
            case rootFirstWinsOrAmbiguous
            /// Nested bodies: last registration wins (shadowing).
            case nestedLastWins
        }
        
        let policy: Policy
        private var bindings = [String: DeclKey]()
        private var ambiguous = Set<String>()
        
        mutating func register(name: String, key: DeclKey) {
            switch policy {
            case .rootFirstWinsOrAmbiguous:
                if ambiguous.contains(name) { return }
                if bindings[name] != nil {
                    bindings.removeValue(forKey: name)
                    ambiguous.insert(name)
                    return
                }
                bindings[name] = key
            case .nestedLastWins:
                bindings[name] = key
            }
        }
        
        func lookup(_ name: String) -> DeclKey? {
            bindings[name]
        }
    }
    
    // MARK: - Phase 1: register decls into the cross-scope root index
    
    private static func registerDeclarations(
        in folder: TreeSitterFolder,
        pathPrefix: String,
        into scope: inout Scope
    ) {
        for subfolder in folder.subfolders {
            registerDeclarations(
                in: subfolder,
                pathPrefix: join(pathPrefix, subfolder.name),
                into: &scope
            )
        }
        
        for file in folder.files {
            let filePath = join(pathPrefix, file.name)
            // File scope: top-level decls are part of the global index; type-like
            // containers also publish their members (see `publishMembersIntoRoot`).
            registerDeclarations(
                file.symbols,
                filePath: filePath,
                into: &scope,
                publishIntoRoot: true
            )
        }
    }
    
    /// Walk a declaration forest for root-index registration.
    ///
    /// - `publishIntoRoot`: whether *these* nodes should be entered into the root
    ///   index. Always true at file scope and under type-like containers; false
    ///   under functions/methods so locals stay body-only.
    private static func registerDeclarations(
        _ symbols: [TreeSitterCodeSymbol],
        filePath: String,
        into scope: inout Scope,
        publishIntoRoot: Bool
    ) {
        for symbol in symbols where symbol.role == .declaration {
            if publishIntoRoot, introducesNameBinding(symbol) {
                scope.register(
                    name: symbol.name,
                    key: DeclKey(filePathRelativeToRoot: filePath, range: symbol.range)
                )
            }
            
            // Type-like containers (incl. extensions) expose members cross-scope.
            // Everything else (functions, properties, …) keeps nested decls local.
            let childPublish = isTypeLikeContainer(symbol)
            registerDeclarations(
                symbol.children,
                filePath: filePath,
                into: &scope,
                publishIntoRoot: childPublish
            )
        }
    }
    
    // MARK: - Phase 2: resolve refs (root already filled; nested scopes only)
    
    private static func resolveFiles(
        in folder: TreeSitterFolder,
        pathPrefix: String,
        stack: inout [Scope],
        usedBy: inout [DeclKey: [TreeSitterCodeSymbol.ReferenceLocation]]
    ) {
        for subfolder in folder.subfolders {
            resolveFiles(
                in: subfolder,
                pathPrefix: join(pathPrefix, subfolder.name),
                stack: &stack,
                usedBy: &usedBy
            )
        }
        
        for file in folder.files {
            let filePath = join(pathPrefix, file.name)
            // File scope: same-file top-level decls beat an ambiguous root name.
            var fileScope = Scope(policy: .nestedLastWins)
            for symbol in file.symbols where symbol.role == .declaration {
                guard introducesNameBinding(symbol) else { continue }
                fileScope.register(
                    name: symbol.name,
                    key: DeclKey(filePathRelativeToRoot: filePath, range: symbol.range)
                )
            }
            stack.append(fileScope)
            process(nodes: file.symbols, filePath: filePath, stack: &stack, usedBy: &usedBy)
            stack.removeLast()
        }
    }
    
    private static func process(
        nodes: [TreeSitterCodeSymbol],
        filePath: String,
        stack: inout [Scope],
        usedBy: inout [DeclKey: [TreeSitterCodeSymbol.ReferenceLocation]]
    ) {
        for node in nodes {
            switch node.role {
            case .reference:
                if let declKey = lookup(node.name, in: stack) {
                    usedBy[declKey, default: []].append(
                        .init(filePathRelativeToRoot: filePath, range: node.range)
                    )
                }
            case .declaration:
                enterDeclBody(node, filePath: filePath, stack: &stack, usedBy: &usedBy)
            }
        }
    }
    
    /// Register sibling decls in a fresh body scope, then process (order-independent locals).
    private static func enterDeclBody(
        _ decl: TreeSitterCodeSymbol,
        filePath: String,
        stack: inout [Scope],
        usedBy: inout [DeclKey: [TreeSitterCodeSymbol.ReferenceLocation]]
    ) {
        var body = Scope(policy: .nestedLastWins)
        for child in decl.children where child.role == .declaration {
            guard introducesNameBinding(child) else { continue }
            body.register(
                name: child.name,
                key: DeclKey(filePathRelativeToRoot: filePath, range: child.range)
            )
        }
        stack.append(body)
        process(nodes: decl.children, filePath: filePath, stack: &stack, usedBy: &usedBy)
        stack.removeLast()
    }
    
    /// Whether a declaration introduces a resolvable name binding.
    ///
    /// Swift `extension T` is still a structural declaration (container for members),
    /// but it does **not** declare type `T` — it extends an existing type. Registering
    /// it under `T` would collide with the real type (root policy then drops the name).
    /// Members *inside* the extension still bind under their own names.
    private static func introducesNameBinding(_ symbol: TreeSitterCodeSymbol) -> Bool {
        symbol.attributes["declaration_kind"] != "extension"
    }
    
    /// Containers whose **members** are part of the cross-scope root index.
    ///
    /// Includes Swift/Python type forms and Swift extensions (`class_declaration`
    /// with `declaration_kind == extension`): the extension itself does not bind
    /// the type name, but methods/properties it declares must be findable outside.
    private static func isTypeLikeContainer(_ symbol: TreeSitterCodeSymbol) -> Bool {
        switch symbol.kind {
        case "class_declaration",    // Swift: class / struct / actor / enum / extension
             "protocol_declaration", // Swift
             "class_definition":     // Python
            return true
        default:
            return false
        }
    }
    
    private static func lookup(_ name: String, in stack: [Scope]) -> DeclKey? {
        for scope in stack.reversed() {
            if let key = scope.lookup(name) { return key }
        }
        return nil
    }
    
    // MARK: - Rebuild forest with used-by attached
    
    private static func rebuild(
        _ folder: TreeSitterFolder,
        pathPrefix: String,
        usedBy: [DeclKey: [TreeSitterCodeSymbol.ReferenceLocation]]
    ) -> TreeSitterFolder {
        TreeSitterFolder(
            name: folder.name,
            files: folder.files.map { file in
                let filePath = join(pathPrefix, file.name)
                return TreeSitterFile(
                    name: file.name,
                    code: file.code,
                    nodes: file.symbols.map { rebuildSymbol($0, filePath: filePath, usedBy: usedBy) }
                )
            },
            subfolders: folder.subfolders.map {
                rebuild($0, pathPrefix: join(pathPrefix, $0.name), usedBy: usedBy)
            }
        )
    }
    
    private static func rebuildSymbol(
        _ symbol: TreeSitterCodeSymbol,
        filePath: String,
        usedBy: [DeclKey: [TreeSitterCodeSymbol.ReferenceLocation]]
    ) -> TreeSitterCodeSymbol {
        let children = symbol.children.map {
            rebuildSymbol($0, filePath: filePath, usedBy: usedBy)
        }
        
        let references: [TreeSitterCodeSymbol.ReferenceLocation]
        if symbol.role == .declaration {
            let key = DeclKey(filePathRelativeToRoot: filePath, range: symbol.range)
            references = usedBy[key] ?? []
        } else {
            references = []
        }
        
        return TreeSitterCodeSymbol(
            role: symbol.role,
            kind: symbol.kind,
            name: symbol.name,
            attributes: symbol.attributes,
            range: symbol.range,
            selectionRange: symbol.selectionRange,
            children: children,
            references: references
        )
    }
    
    // MARK: - Paths
    
    private static func join(_ prefix: String, _ component: String) -> String {
        prefix.isEmpty ? component : prefix + "/" + component
    }
}

extension TreeSitterFolder {
    /// Forest copy with declaration `references` filled via scope-stack name resolution.
    func withLinkedReferences() -> TreeSitterFolder {
        TreeSitterReferenceLinker.link(self)
    }
}
