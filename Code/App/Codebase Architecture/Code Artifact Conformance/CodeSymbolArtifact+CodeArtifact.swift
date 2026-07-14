import SwiftyToolz

extension CodeSymbolArtifact: SearchableCodeArtifact
{
    func contains(fileLine: Int) -> Bool
    {
        fileLine >= range.start.line && fileLine <= range.end.line
    }
}

extension CodeSymbolArtifact: CodeArtifact
{
    var parts: [any CodeArtifact]
    {
        subsymbolGraph.nodesByID.values.map { $0.value }
    }
    
    var intrinsicSizeInLinesOfCode: Int? { (range.end.line - range.start.line) + 1 }
    
    var kindName: String { kind }
    
    var lineNumber: Int? { selectionRange.start.line }
    
    // MARK: - Hashability
    
    static func == (lhs: CodeSymbolArtifact,
                    rhs: CodeSymbolArtifact) -> Bool { lhs === rhs }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
