/**
 ⛔️ Do not change! This is part of the ".codebase" file format.
 */
final class LSPCodeFolder: Codable, Sendable
{
    var looksLikeAPackage: Bool
    {
        if name.lowercased().contains("package") { return true }
        
        return files?.contains { $0.name.lowercased().contains("package") } ?? false
    }
    
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
