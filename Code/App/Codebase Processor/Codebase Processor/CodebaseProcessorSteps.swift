import Foundation
import SwiftLSP
import SwiftyToolz

/// Namespace to get the actual processing off the main actor
@BackgroundActor
enum CodebaseProcessorSteps
{
    static func readFolder(from location: CodebaseLocation) throws -> LSPCodeFolder?
    {
        try location.folder.mapSecurityScoped
        {
            guard let codeFolder = try LSPCodeFolder($0, codeFileEndings: location.codeFileEndings) else
            {
                throw "Project folder contains no code files with the specified file endings\nFolder: \($0.absoluteString)\nFile endings: \(location.codeFileEndings)"
            }
            
            return codeFolder
        }
    }
    
    static func retrieveSymbolsAndReferences(for codebase: LSPCodeFolder,
                                             from server: LSP.Server,
                                             codebaseRootFolder: URL) async throws -> LSPCodeFolder
    {
        try await codebase.retrieveSymbolsAndReferences(from: server,
                                                        codebaseRootFolder: codebaseRootFolder)
    }
    
    // MARK: - Architecture (LSP vs Tree-sitter factories)
    
    static func generateArchitecture(from folder: LSPCodeFolder) -> CodeFolderArtifact
    {
        var extraReferences = [LSPCodeSymbol.ReferenceLocation]()
        
        return CodeFolderArtifact(codeFolder: folder,
                                  pathInRootFolder: .root,
                                  additionalReferences: &extraReferences)
    }
    
    static func generateArchitecture(fromTreeSitterForest forest: TreeSitterFolder) -> CodeFolderArtifact
    {
        CodeFolderArtifact(treeSitterFolder: forest)
    }
}
