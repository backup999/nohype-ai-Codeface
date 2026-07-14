import Foundation
import FoundationToolz
import UniformTypeIdentifiers

/// On-disk `.codebase` payload (same JSON shape as the former `FileDocument`).
struct CodebaseFilePayload: Codable
{
    var codebase: LSPCodeFolder?
}

enum CodebaseFileIO
{
    /// Load a `CodeFolder` from a `.codebase` file.
    /// Prefers the document wrapper `{ "codebase": … }`; falls back to a root `CodeFolder`.
    static func loadCodeFolder(from fileURL: URL) throws -> LSPCodeFolder
    {
        let data = try Data(contentsOf: fileURL)
        
        if let payload = try? CodebaseFilePayload(jsonData: data),
           let codebase = payload.codebase
        {
            return codebase
        }
        
        return try LSPCodeFolder(jsonData: data)
    }
    
    /// Write a `CodeFolder` as a `.codebase` file (wrapper format, non-pretty, unescaped slashes).
    static func export(_ codeFolder: LSPCodeFolder, to fileURL: URL) throws
    {
        let data = try CodebaseFilePayload(codebase: codeFolder)
            .encode(options: .withoutEscapingSlashes) as Data
        try data.write(to: fileURL, options: .atomic)
    }
}

extension UTType
{
    static let codebase = UTType(exportedAs: "com.flowtoolz.codeface.codebase")
}
