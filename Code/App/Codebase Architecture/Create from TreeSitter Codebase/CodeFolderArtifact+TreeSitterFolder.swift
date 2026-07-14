import SwiftNodes
import SwiftyToolz

/// Tree-sitter → Architecture (declarations only; empty dependency graphs in iter 1).
@BackgroundActor
extension CodeFolderArtifact {
    convenience init(treeSitterFolder: TreeSitterFolder) {
        var ultimateFolder = treeSitterFolder
        
        while let onlySubfolder = ultimateFolder.containsExactlyOneSubfolder {
            ultimateFolder = TreeSitterFolder(
                name: ultimateFolder.name + "/" + onlySubfolder.name,
                files: onlySubfolder.files,
                subfolders: onlySubfolder.subfolders
            )
        }
        
        var graph = Graph<CodeArtifact.ID, Part, Int>()
        
        for subfolder in ultimateFolder.subfolders {
            graph.insert(Part(kind: .subfolder(.init(treeSitterFolder: subfolder))))
        }
        
        for file in ultimateFolder.files {
            graph.insert(Part(kind: .file(.init(treeSitterFile: file))))
        }
        
        graph.filterEssentialEdges()
        self.init(name: ultimateFolder.name, partGraph: graph)
    }
}

private extension TreeSitterFolder {
    var containsExactlyOneSubfolder: TreeSitterFolder? {
        if !files.isEmpty { return nil }
        guard subfolders.count == 1 else { return nil }
        return subfolders.first
    }
}
