/// Multi-file Tree-sitter structure IR (paths + text + `CodeNode` trees).
///
/// Analogous to the LSP `CodeFolder` dump, but filename texts and structure come
/// from in-process parsing alone. Not part of the `.codebase` file format.
final class TreeSitterFolder: Sendable {
    init(name: String,
         files: [TreeSitterFile] = [],
         subfolders: [TreeSitterFolder] = [])
    {
        self.name = name
        self.files = files
        self.subfolders = subfolders
    }
    
    let name: String
    let files: [TreeSitterFile]
    let subfolders: [TreeSitterFolder]
    
    /// Mirrors `CodeFolder.looksLikeAPackage` for view-model package icon choice.
    var looksLikeAPackage: Bool {
        if name.lowercased().contains("package") { return true }
        return files.contains { $0.name.lowercased().contains("package") }
    }
}

/// One source file’s text and top-level code-tree nodes.
final class TreeSitterFile: Sendable {
    init(name: String, code: String, nodes: [CodeNode]) {
        self.name = name
        self.code = code
        self.nodes = nodes
    }
    
    let name: String
    let code: String
    let nodes: [CodeNode]
    
    var lines: [String] { code.lines }
}
