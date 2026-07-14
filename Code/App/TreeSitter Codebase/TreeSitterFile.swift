/// One source file’s text and top-level code-tree nodes.
final class TreeSitterFile: Sendable {
    init(name: String, code: String, nodes: [TreeSitterCodeSymbol]) {
        self.name = name
        self.code = code
        self.nodes = nodes
    }
    
    let name: String
    let code: String
    let nodes: [TreeSitterCodeSymbol]
    
    var lines: [String] { code.lines }
}
