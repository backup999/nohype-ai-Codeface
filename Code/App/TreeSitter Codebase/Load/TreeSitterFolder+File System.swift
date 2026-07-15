import Foundation
import SwiftLSP

extension TreeSitterFolder {
    static func readFolder(from location: LSP.CodebaseLocation) throws -> TreeSitterFolder
    {
        guard let language = location.language else {
            throw "Could not read codebase from \(location.folder.path) using TreeSitter because we do not support the language \(location.languageName) yet."
        }
        
        return try location.folder.mapSecurityScoped
        {
            try TreeSitterFolder(url: $0,
                                 fileEndings: location.codeFileEndings,
                                 language: language)
        }
    }
    
    convenience init(url: URL, fileEndings: [String], language: LanguageProfile) throws {
        // TODO: read directly from file, equivalent to how `LSPCodeFolder+File System.swift` does it. Of course the LSP path stops at the file level and adds symbols later. But here we can generate the symbols within each file right away using TreeSitter, see example below.
        /**
         example of how to generate the symbols for a file:
         
         ```swift
         let code = "some source code"
         TreeSitterFile(name: "some file name",
                        code: code,
                        symbols: try CodeTreeGenerator.generateTree(from: code, language: language))
         ```
         */
        
        throw "not implemented yet"
    }
}

extension LSP.CodebaseLocation {
    var language: LanguageProfile? {
        return switch languageName.lowercased() {
        case "swift": .swift
        case "python": .python
        default : nil
        }
    }
}
