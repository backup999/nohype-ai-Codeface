import Foundation
import FoundationToolz
import SwiftLSP
import SwiftyToolz

/// Text-bearing file tree + Tree-sitter structure (independent of LSP symbols).
struct TreeSitterLoadResult: Sendable {
    /// Folder/file text only (export cache; no symbol population).
    let sourceTree: CodeFolder
    /// Filtered, role-tagged structure IR.
    let forest: TreeSitterFolder
}

/// Folder → Tree-sitter forest (no Language Server, no `CodeSymbol`).
enum TreeSitterCodebaseExtractor {
    
    // MARK: - App entry
    
    /// Security-scoped FS read (same helper as LSP load) + parse into IR.
    static func load(from location: LSP.CodebaseLocation) throws -> TreeSitterLoadResult {
        try location.folder.mapSecurityScoped { folderURL in
            guard let sourceTree = try CodeFolder(folderURL,
                                                  codeFileEndings: location.codeFileEndings)
            else {
                throw "Project folder contains no code files with the specified file endings\nFolder: \(folderURL.absoluteString)\nFile endings: \(location.codeFileEndings)"
            }
            let forest = try extract(from: sourceTree)
            return TreeSitterLoadResult(sourceTree: sourceTree, forest: forest)
        }
    }
    
    // MARK: - Core
    
    static func extract(from codeFolder: CodeFolder) throws -> TreeSitterFolder {
        try project(codeFolder)
    }
    
    static func extract(folderURL: URL,
                        codeFileEndings: [String]) throws -> TreeSitterFolder?
    {
        guard let codeFolder = try CodeFolder(folderURL, codeFileEndings: codeFileEndings)
        else { return nil }
        return try extract(from: codeFolder)
    }
    
    // MARK: - Project
    
    private static func project(_ folder: CodeFolder) throws -> TreeSitterFolder {
        let files = try (folder.files ?? []).map(project(file:))
        let subfolders = try (folder.subfolders ?? []).map(project)
        return TreeSitterFolder(name: folder.name,
                                files: files,
                                subfolders: subfolders)
    }
    
    private static func project(file: CodeFile) throws -> TreeSitterFile {
        let ext = (file.name as NSString).pathExtension
        guard let language = SourceLanguage.from(fileExtension: ext) else {
            return TreeSitterFile(name: file.name, code: file.code, nodes: [])
        }
        let nodes = try CodeTreeGenerator.generateTree(from: file.code, language: language)
        return TreeSitterFile(name: file.name, code: file.code, nodes: nodes)
    }
}
