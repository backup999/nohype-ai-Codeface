import SwiftNodes
import SwiftyToolz

@BackgroundActor
extension CodeSymbolArtifact {
    convenience init(symbol: TreeSitterCodeSymbol,
                     linesOfEnclosingFile: [String],
                     pathInRootFolder: RelativeFilePath,
                     additionalReferences: inout [TreeSitterCodeSymbol.ReferenceLocation]) {
        var graph = Graph<CodeArtifact.ID, CodeSymbolArtifact, Int>()
        var referencesByChildID = [CodeArtifact.ID: [TreeSitterCodeSymbol.ReferenceLocation]]()
        
        // create subsymbols recursively – RECURSION FIRST
        // Full Tree-sitter tree: declarations and reference sites alike.
        
        for childSymbol in symbol.children {
            var extraChildReferences = [TreeSitterCodeSymbol.ReferenceLocation]()
            
            let child = CodeSymbolArtifact(symbol: childSymbol,
                                           linesOfEnclosingFile: linesOfEnclosingFile,
                                           pathInRootFolder: pathInRootFolder,
                                           additionalReferences: &extraChildReferences)
            
            let childReferences = (childSymbol.references ?? []) + extraChildReferences
            
            referencesByChildID[child.id] = childReferences
            
            graph.insert(child)
        }
        
        // base case: create this symbol artifact
        
        let thisRange = symbol.range
        
        for (childID, childReferences) in referencesByChildID {
            for childReference in childReferences {
                if pathInRootFolder.string == childReference.filePathRelativeToRoot,
                   thisRange.contains(childReference.range) {
                    // we found a reference within the scope of this symbol artifact that we initialize
                    
                    // search for a sibling that contains the reference location
                    for sibling in graph.values {
                        if sibling.id == childID { continue } // not a sibling but the same child
                        
                        if sibling.range.contains(childReference.range) {
                            // the sibling references (depends on) the child -> add edge and leave for loop
                            graph.add(1, toEdgeFrom: sibling.id, to: childID)
                            break
                        }
                    }
                } else {
                    // we found an out-of-scope reference that we pass on to the caller
                    additionalReferences += childReference
                }
            }
        }
        
        graph.filterEssentialEdges()
        
        let code = thisRange.getCode(fromLines: linesOfEnclosingFile)
        let kind = SymbolKindDisplay.kindName(
            nodeKind: symbol.kind,
            refinedKind: symbol.attributes["declaration_kind"]
        )
        
        self.init(name: symbol.name,
                  kind: kind,
                  range: thisRange,
                  selectionRange: symbol.selectionRange,
                  code: code ?? "",
                  subsymbolGraph: graph)
    }
}
