/**
 ⛔️ Do not change! This is part of the ".codebase" file format.
 */
final class LSPCodeFolder: Codable, Sendable
{
    init(name: String,
         files: [LSPCodeFile] = [],
         subfolders: [LSPCodeFolder] = [])
    {
        self.name = name
        self.files = files.isEmpty ? nil : files
        self.subfolders = subfolders.isEmpty ? nil : subfolders
    }
    
    let name: String
    let files: [LSPCodeFile]?
    let subfolders: [LSPCodeFolder]?
}
