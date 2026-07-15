import SwiftNodes
import SwiftyToolz

@BackgroundActor
extension CodeFileArtifact {
    /// Top-level declarations only; references stay in the IR for later linking.
    convenience init(treeSitterFile: TreeSitterFile) {
        var graph = Graph<CodeArtifact.ID, CodeSymbolArtifact, Int>()
        
        for node in treeSitterFile.symbols where node.role == .declaration {
            graph.insert(CodeSymbolArtifact(declaration: node,
                                            linesOfEnclosingFile: treeSitterFile.code.lines))
        }
        
        graph.filterEssentialEdges()
        
        self.init(name: treeSitterFile.name,
                  codeLines: treeSitterFile.code.lines,
                  symbolGraph: graph)
    }
}
