import SwiftLSP
import SwiftNodes
import SwiftyToolz

@BackgroundActor
extension CodeSymbolArtifact
{
    convenience init(symbol: LSPCodeSymbol,
                     linesOfEnclosingFile: [String],
                     pathInRootFolder: RelativeFilePath,
                     additionalReferences: inout [LSPCodeSymbol.ReferenceLocation])
    {
        var graph = Graph<CodeArtifact.ID, CodeSymbolArtifact, Int>()
        var referencesByChildID = [CodeArtifact.ID: [LSPCodeSymbol.ReferenceLocation]]()
        
        // create subsymbols recursively – RECURSION FIRST
        
        for childSymbol in (symbol.children ?? [])
        {
            var extraChildReferences = [LSPCodeSymbol.ReferenceLocation]()
            
            let child = CodeSymbolArtifact(symbol: childSymbol,
                                           linesOfEnclosingFile: linesOfEnclosingFile,
                                           pathInRootFolder: pathInRootFolder,
                                           additionalReferences: &extraChildReferences)
            
            let childReferences = (childSymbol.references ?? []) + extraChildReferences
            
            referencesByChildID[child.id] = childReferences
            
            graph.insert(child)
        }
        
        // base case: create this symbol artifact
        
        let thisRange = CodeRange(symbol.range)
        
        for (childID, childReferences) in referencesByChildID
        {
            for childReference in childReferences
            {
                if pathInRootFolder.string == childReference.filePathRelativeToRoot,
                   thisRange.contains(CodeRange(childReference.range))
                {
                    // we found a reference within the scope of this symbol artifact that we initialize
                    
                    // search for a sibling that contains the reference location
                    for sibling in graph.values
                    {
                        if sibling.id == childID { continue } // not a sibling but the same child
                        
                        if sibling.range.contains(CodeRange(childReference.range))
                        {
                            // the sibling references (depends on) the child -> add edge and leave for loop
                            graph.add(1, toEdgeFrom: sibling.id, to: childID)
                            break
                        }
                    }
                }
                else
                {
                    // we found an out-of-scope reference that we pass on to the caller
                    additionalReferences += childReference
                }
            }
        }
        
        graph.filterEssentialEdges()
        
        let code = getCode(of: thisRange,
                           inFileLines: linesOfEnclosingFile)
        
        self.init(name: symbol.name,
                  kind: symbol.kind.name,
                  range: thisRange,
                  selectionRange: CodeRange(symbol.selectionRange),
                  code: code ?? "",
                  subsymbolGraph: graph)
    }
}

func getCode(of range: CodeRange, inFileLines fileLines: [String]) -> String?
{
    guard fileLines.isValid(index: range.start.line),
          fileLines.isValid(index: range.end.line) else { return nil }
    
    return fileLines[range.start.line ... range.end.line].joined(separator: "\n")
}
