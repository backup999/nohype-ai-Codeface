import SwiftNodes
import SwiftyToolz

@BackgroundActor
extension CodeFileArtifact {
    convenience init(codeFile: TreeSitterFile,
                     pathInRootFolder: RelativeFilePath,
                     additionalReferences: inout [TreeSitterCodeSymbol.ReferenceLocation]) {
        var graph = Graph<CodeArtifact.ID, CodeSymbolArtifact, Int>()
        var referencesByChildID = [CodeArtifact.ID: [TreeSitterCodeSymbol.ReferenceLocation]]()
        
        // create child symbols recursively – DEPTH FIRST
        
        // declarations and reference sites alike — Tree-sitter IR is richer than LSP
        for childSymbol in codeFile.symbols {
            var extraReferences = [TreeSitterCodeSymbol.ReferenceLocation]()
            
            let child = CodeSymbolArtifact(symbol: childSymbol,
                                           linesOfEnclosingFile: codeFile.code.lines,
                                           pathInRootFolder: pathInRootFolder,
                                           additionalReferences: &extraReferences)
            
            let childReferences = (childSymbol.references ?? []) + extraReferences
            referencesByChildID[child.id] = childReferences
            
            graph.insert(child)
        }
        
        // base case: create this file artifact
        
        for (childID, childReferences) in referencesByChildID {
            for childReference in childReferences {
                if pathInRootFolder.string == childReference.filePathRelativeToRoot {
                    // we found a reference within the scope of this file artifact that we initialize
                    
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
        
        self.init(name: codeFile.name,
                  codeLines: codeFile.code.lines,
                  symbolGraph: graph)
    }
}
