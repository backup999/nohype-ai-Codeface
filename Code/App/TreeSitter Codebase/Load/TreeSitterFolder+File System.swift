import Foundation
import SwiftLSP

extension TreeSitterFolder {
    static func readFolder(from location: LSP.CodebaseLocation) throws -> TreeSitterFolder
    {
        try location.folder.mapSecurityScoped
        {
            try TreeSitterFolder(url: $0, fileEndings: location.codeFileEndings)
        }
    }
    
    convenience init(url: URL, fileEndings: [String]) throws {
        // TODO: read directly from file equivalent to how `LSPCodeFolder+File System.swift` does it
        throw "not implemented yet"
    }
    
    private static func extract(from codeFolder: LSPCodeFolder) throws -> TreeSitterFolder {
        try convert(codeFolder)
    }
    
    private static func convert(_ folder: LSPCodeFolder) throws -> TreeSitterFolder {
        let files = try (folder.files ?? []).map(convert(file:))
        let subfolders = try (folder.subfolders ?? []).map(convert)
        return TreeSitterFolder(name: folder.name,
                                files: files,
                                subfolders: subfolders)
    }
    
    private static func convert(file: LSPCodeFile) throws -> TreeSitterFile {
        let ext = (file.name as NSString).pathExtension
        guard let language = SourceLanguage.from(fileExtension: ext) else {
            return TreeSitterFile(name: file.name, code: file.code, nodes: [])
        }
        let nodes = try CodeTreeGenerator.generateTree(from: file.code, language: language)
        return TreeSitterFile(name: file.name, code: file.code, nodes: nodes)
    }
}
