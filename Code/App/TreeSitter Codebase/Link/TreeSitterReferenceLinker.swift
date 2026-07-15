/// Scope-stack name resolution (v0): refs → decls → used-by on declarations.
///
/// Pure: `TreeSitterFolder` → new forest with `references` filled on matched decls.
/// No types, overloads, or imports — exact name match, most-local scope wins.
enum TreeSitterReferenceLinker {
    
    // MARK: - Public
    
    static func link(_ folder: TreeSitterFolder) -> TreeSitterFolder {
        var root = Scope(policy: .rootFirstWinsOrAmbiguous)
        registerTopLevelDeclarations(in: folder, pathPrefix: "", into: &root)
        
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
            /// File-level / root: first registration wins; a second distinct decl
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
    
    // MARK: - Phase 1: register file-level decls into root
    
    private static func registerTopLevelDeclarations(
        in folder: TreeSitterFolder,
        pathPrefix: String,
        into scope: inout Scope
    ) {
        for subfolder in folder.subfolders {
            registerTopLevelDeclarations(
                in: subfolder,
                pathPrefix: join(pathPrefix, subfolder.name),
                into: &scope
            )
        }
        
        for file in folder.files {
            let filePath = join(pathPrefix, file.name)
            for symbol in file.symbols where symbol.role == .declaration {
                scope.register(
                    name: symbol.name,
                    key: DeclKey(filePathRelativeToRoot: filePath, range: symbol.range)
                )
            }
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
            process(nodes: file.symbols, filePath: filePath, stack: &stack, usedBy: &usedBy)
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
            body.register(
                name: child.name,
                key: DeclKey(filePathRelativeToRoot: filePath, range: child.range)
            )
        }
        stack.append(body)
        process(nodes: decl.children, filePath: filePath, stack: &stack, usedBy: &usedBy)
        stack.removeLast()
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
