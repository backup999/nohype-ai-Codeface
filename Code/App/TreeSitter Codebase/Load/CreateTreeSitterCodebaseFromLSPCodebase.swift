import Foundation

enum CreateTreeSitterCodebaseFromLSPCodebase {
    static func extract(from codeFolder: LSPCodeFolder) throws -> TreeSitterFolder {
        try project(codeFolder)
    }
    
    private static func project(_ folder: LSPCodeFolder) throws -> TreeSitterFolder {
        let files = try (folder.files ?? []).map(project(file:))
        let subfolders = try (folder.subfolders ?? []).map(project)
        return TreeSitterFolder(name: folder.name,
                                files: files,
                                subfolders: subfolders)
    }
    
    private static func project(file: LSPCodeFile) throws -> TreeSitterFile {
        let ext = (file.name as NSString).pathExtension
        guard let language = SourceLanguage.from(fileExtension: ext) else {
            return TreeSitterFile(name: file.name, code: file.code, nodes: [])
        }
        let nodes = try CodeTreeGenerator.generateTree(from: file.code, language: language)
        return TreeSitterFile(name: file.name, code: file.code, nodes: nodes)
    }
}
