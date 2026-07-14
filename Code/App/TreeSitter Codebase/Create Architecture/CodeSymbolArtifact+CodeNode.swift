import SwiftNodes
import SwiftyToolz

@BackgroundActor
extension CodeSymbolArtifact {
    /// Nested declarations only; empty edge graph (iteration 1).
    convenience init(declaration node: CodeNode, linesOfEnclosingFile: [String]) {
        precondition(node.role == .declaration)
        
        var graph = Graph<CodeArtifact.ID, CodeSymbolArtifact, Int>()
        
        for child in node.children where child.role == .declaration {
            graph.insert(CodeSymbolArtifact(declaration: child,
                                            linesOfEnclosingFile: linesOfEnclosingFile))
        }
        
        graph.filterEssentialEdges()
        
        let code = getCode(of: node.range, inFileLines: linesOfEnclosingFile) ?? ""
        let kind = SymbolKindDisplay.kindName(
            nodeKind: node.kind,
            refinedKind: node.attributes["declaration_kind"]
        )
        
        self.init(
            name: node.name,
            kind: kind,
            range: node.range,
            selectionRange: node.selectionRange,
            code: code,
            subsymbolGraph: graph
        )
    }
}
