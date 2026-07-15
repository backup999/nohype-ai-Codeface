/// Multi-file Tree-sitter structure IR (paths + text + `CodeNode` trees).
///
/// Analogous to the `LSPCodeFolder` dump, but filename texts and structure come
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
}
