import FoundationToolz
import Foundation
import SwiftLSP
import SwiftyToolz

extension TreeSitterFolder {
    static func readFolder(from location: LSP.CodebaseLocation) throws -> TreeSitterFolder
    {
        guard let language = location.language else {
            throw "Could not read codebase from \(location.folder.path) using TreeSitter because we do not support the language \(location.languageName) yet."
        }
        
        return try location.folder.mapSecurityScoped
        {
            guard let folder = try TreeSitterFolder(url: $0,
                                                    fileEndings: location.codeFileEndings,
                                                    language: language)
            else {
                throw "Project folder contains no code files with the specified file endings\nFolder: \($0.absoluteString)\nFile endings: \(location.codeFileEndings)"
            }
            
            return folder
        }
    }
    
    convenience init?(url: URL, fileEndings: [String], language: SourceLanguage) throws {
        let fileManager = FileManager.default
        
        let urls = fileManager.items(inDirectory: url, recursive: false)
        
        var files = [TreeSitterFile]()
        var subfolders = [TreeSitterFolder]()
        
        for itemURL in urls
        {
            if itemURL.isDirectory
            {
                if let subfolder = try TreeSitterFolder(url: itemURL,
                                                        fileEndings: fileEndings,
                                                        language: language)
                {
                    subfolders += subfolder
                }
            }
            else if fileEndings.contains(itemURL.pathExtension)
            {
                files += try TreeSitterFile(url: itemURL, language: language)
            }
        }
        
        if files.count + subfolders.count == 0 { return nil }
        
        self.init(name: url.lastPathComponent,
                  files: files,
                  subfolders: subfolders)
    }
}

private extension TreeSitterFile {
    convenience init(url: URL, language: SourceLanguage) throws {
        let code = try String(contentsOf: url, encoding: .utf8)
        
        self.init(name: url.lastPathComponent,
                  code: code,
                  nodes: try CodeTreeGenerator.generateTree(from: code,
                                                            language: language))
    }
}

extension LSP.CodebaseLocation {
    var language: SourceLanguage? {
        return switch languageName.lowercased() {
        case "swift": .swift
        case "python": .python
        default : nil
        }
    }
}
