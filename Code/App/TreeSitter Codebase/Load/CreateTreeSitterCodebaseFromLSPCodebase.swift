import Foundation
import SwiftLSP

enum CreateTreeSitterCodebaseFromLSPCodebase {
    static func load(fromFolder folder: LSP.CodebaseLocation) throws -> TreeSitterFolder {
        throw "not implemented yet"
    }
    
    static func extract(from codeFolder: LSPCodeFolder) throws -> TreeSitterFolder {
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
