import Foundation
import FoundationToolz
import UniformTypeIdentifiers

/// On-disk `.codebase` payload (same JSON shape as the former `FileDocument`).
struct CodebaseFilePayload: Codable
{
    var codebase: CodeFolder?
}

enum CodebaseFileIO
{
    /// Load a `CodeFolder` from a `.codebase` file.
    /// Prefers the document wrapper `{ "codebase": … }`; falls back to a root `CodeFolder`.
    static func loadCodeFolder(from fileURL: URL) throws -> CodeFolder
    {
        let data = try Data(contentsOf: fileURL)
        
        if let payload = try? CodebaseFilePayload(jsonData: data),
           let codebase = payload.codebase
        {
            return codebase
        }
        
        return try CodeFolder(jsonData: data)
    }
    
    /// Write a `CodeFolder` as a `.codebase` file (wrapper format, non-pretty, unescaped slashes).
    static func export(_ codeFolder: CodeFolder, to fileURL: URL) throws
    {
        let payload = CodebaseFilePayload(codebase: codeFolder)
        let data = try payload.encode(options: .withoutEscapingSlashes) as Data
        try data.write(to: fileURL, options: .atomic)
    }
}

extension UTType
{
    static let codebase = UTType(exportedAs: "com.flowtoolz.codeface.codebase")
}
