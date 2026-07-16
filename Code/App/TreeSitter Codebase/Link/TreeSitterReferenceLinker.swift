/// Scope-stack name resolution (v0): refs → decls → used-by on declarations.
///
/// Pure: `TreeSitterFolder` → new forest with `references` filled on matched decls.
/// No types, overloads, or imports — exact name match, most-local scope wins.
///
/// ## Scopes (mirror the forest)
///
/// 1. **Folder scopes (every depth, including the codebase root):** all name-binding
///    decls in that folder’s **subtree** (file-level + members of type-like
///    containers). First registration wins; a second distinct binding makes the
///    name **ambiguous** at that level.
/// 2. **File scopes:** that file’s top-level name-binding decls, last-wins.
/// 3. **Nested body scopes:** child decls of a declaration, last-wins shadowing.
///
/// Lookup walks the stack inward→outward. A name unique under a closer folder
/// still resolves when an outer folder (or the root) marks it ambiguous.
/// Function/method bodies do **not** publish nested locals into folder scopes.
///
/// ## Qualified calls (`Type.method` / `host.method`)
///
/// Call refs keep the bare method name for lookup, plus optional `call_host`.
/// When the host **looks like a type** (UpperCamelCase) and is **not** bound in
/// any scope, the method name is **not** linked — otherwise `Library.run()` /
/// `BackgroundActor.run` would attach used-by to an unrelated `run` elsewhere.
/// Instance hosts (`host.method`, lowercase) still use bare-method lookup.
enum TreeSitterReferenceLinker {
    
    // MARK: - Public
    
    static func link(_ folder: TreeSitterFolder) -> TreeSitterFolder {
        var usedBy = [DeclKey: [TreeSitterCodeSymbol.ReferenceLocation]]()
        var stack = [Scope]()
        enterFolder(folder, pathPrefix: "", stack: &stack, usedBy: &usedBy)
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
            /// Folder / codebase: first registration wins; a second distinct decl
            /// with the same name makes the name unresolvable (ambiguous).
            case firstWinsOrAmbiguous
            /// File top-level and nested bodies: last registration wins (shadowing).
            case lastWins
        }
        
        let policy: Policy
        private var bindings = [String: DeclKey]()
        private var ambiguous = Set<String>()
        
        mutating func register(name: String, key: DeclKey) {
            switch policy {
            case .firstWinsOrAmbiguous:
                if ambiguous.contains(name) { return }
                if bindings[name] != nil {
                    bindings.removeValue(forKey: name)
                    ambiguous.insert(name)
                    return
                }
                bindings[name] = key
            case .lastWins:
                bindings[name] = key
            }
        }
        
        func lookup(_ name: String) -> DeclKey? {
            bindings[name]
        }
    }
    
    // MARK: - Walk: folder → file → bodies
    
    /// Push a folder scope filled with this subtree, then recurse and process files.
    private static func enterFolder(
        _ folder: TreeSitterFolder,
        pathPrefix: String,
        stack: inout [Scope],
        usedBy: inout [DeclKey: [TreeSitterCodeSymbol.ReferenceLocation]]
    ) {
        var folderScope = Scope(policy: .firstWinsOrAmbiguous)
        registerSubtree(folder, pathPrefix: pathPrefix, into: &folderScope)
        stack.append(folderScope)
        
        for subfolder in folder.subfolders {
            enterFolder(
                subfolder,
                pathPrefix: join(pathPrefix, subfolder.name),
                stack: &stack,
                usedBy: &usedBy
            )
        }
        
        for file in folder.files {
            enterFile(
                file,
                filePath: join(pathPrefix, file.name),
                stack: &stack,
                usedBy: &usedBy
            )
        }
        
        stack.removeLast()
    }
    
    /// Push a file scope (top-level name bindings only), then resolve refs/bodies.
    private static func enterFile(
        _ file: TreeSitterFile,
        filePath: String,
        stack: inout [Scope],
        usedBy: inout [DeclKey: [TreeSitterCodeSymbol.ReferenceLocation]]
    ) {
        var fileScope = Scope(policy: .lastWins)
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
    
    // MARK: - Register decls into a folder scope (full subtree)
    
    private static func registerSubtree(
        _ folder: TreeSitterFolder,
        pathPrefix: String,
        into scope: inout Scope
    ) {
        for subfolder in folder.subfolders {
            registerSubtree(
                subfolder,
                pathPrefix: join(pathPrefix, subfolder.name),
                into: &scope
            )
        }
        
        for file in folder.files {
            registerDeclarations(
                file.symbols,
                filePath: join(pathPrefix, file.name),
                into: &scope,
                publishIntoContainer: true
            )
        }
    }
    
    /// Walk a declaration forest for container-scope registration.
    ///
    /// - `publishIntoContainer`: whether *these* nodes should be entered into the
    ///   current folder scope. Always true at file scope and under type-like
    ///   containers; false under functions/methods so locals stay body-only.
    private static func registerDeclarations(
        _ symbols: [TreeSitterCodeSymbol],
        filePath: String,
        into scope: inout Scope,
        publishIntoContainer: Bool
    ) {
        for symbol in symbols where symbol.role == .declaration {
            if publishIntoContainer, introducesNameBinding(symbol) {
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
                publishIntoContainer: childPublish
            )
        }
    }
    
    // MARK: - Resolve refs inside a file
    
    private static func process(
        nodes: [TreeSitterCodeSymbol],
        filePath: String,
        stack: inout [Scope],
        usedBy: inout [DeclKey: [TreeSitterCodeSymbol.ReferenceLocation]]
    ) {
        for node in nodes {
            switch node.role {
            case .reference:
                guard shouldAttemptNameLookup(node, stack: stack) else { continue }
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
        var body = Scope(policy: .lastWins)
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
    /// it under `T` would collide with the real type (folder policy then drops the name).
    /// Members *inside* the extension still bind under their own names.
    private static func introducesNameBinding(_ symbol: TreeSitterCodeSymbol) -> Bool {
        symbol.attributes["declaration_kind"] != "extension"
    }
    
    /// Containers whose **members** are part of folder/cross-scope indexes.
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
    
    /// Whether a reference should try exact-name lookup against the scope stack.
    ///
    /// Qualified calls with an **unresolved type-like host** skip lookup so the
    /// bare method name cannot glue onto an unrelated same-named method in the
    /// forest (`Library.run` ↛ `Processor.run`).
    private static func shouldAttemptNameLookup(
        _ node: TreeSitterCodeSymbol,
        stack: [Scope]
    ) -> Bool {
        guard let host = node.attributes[LanguageProfile.callHostAttribute],
              looksLikeTypeName(host)
        else {
            return true
        }
        return lookup(host, in: stack) != nil
    }
    
    /// Swift/Python type names are UpperCamelCase; instance receivers are not.
    private static func looksLikeTypeName(_ name: String) -> Bool {
        guard let first = name.first else { return false }
        return first.isUppercase
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
