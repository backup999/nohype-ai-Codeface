import SwiftNodes

final class CodeSymbolArtifact: Identifiable, Hashable, Sendable
{
    // MARK: - Initialization
    
    init(name: String,
         kind: String,
         range: CodeRange,
         selectionRange: CodeRange,
         code: String,
         subsymbolGraph: Graph<CodeArtifact.ID, CodeSymbolArtifact, Int>)
    {
        self.name = name
        self.kind = kind
        self.range = range
        self.selectionRange = selectionRange
        self.code = code
        self.subsymbolGraph = subsymbolGraph
    }
    
    // MARK: - Graph Structure
    
    let subsymbolGraph: Graph<CodeArtifact.ID, CodeSymbolArtifact, Int>
    
    // MARK: - Basics
    
    let id: CodeArtifact.ID = .randomID()
    let name: String
    /// Display-oriented free-string kind (readable label from structure producer).
    let kind: String
    let range: CodeRange
    let selectionRange: CodeRange
    let code: String?
}
