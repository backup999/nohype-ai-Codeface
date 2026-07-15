import SwiftNodes
import SwiftyToolz

/// Tree-sitter → Architecture (declarations only; empty dependency graphs in iter 1).
@BackgroundActor
extension CodeFolderArtifact {
    convenience init(codeFolder: TreeSitterFolder,
                     pathInRootFolder: RelativeFilePath,
                     additionalReferences: inout [TreeSitterCodeSymbol.ReferenceLocation]) {
        // TODO: implement equivalent to how `CodeFolderArtifact+LSPCodeFolder.swift` does it. Do not reuse anything fromn the LSP path but rather create a perfect mirror image of the LSP path here.
        fatalError("not implemented yet")
    }
}

private extension TreeSitterFolder {
    var containsExactlyOneSubfolder: TreeSitterFolder? {
        if !files.isEmpty { return nil }
        guard subfolders.count == 1 else { return nil }
        return subfolders.first
    }
}
