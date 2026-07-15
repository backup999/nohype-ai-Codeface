import Foundation

/**
 Demarcates a codebase in the file system: by location, language and source file types. Exactly mirrors the same type from SwiftLSP but is independent of SwiftLSP just as the concept is independent of LSP
 */
struct CodebaseLocation: Codable, Equatable, Sendable {
    
    public init(folder: URL,
                languageName: String,
                codeFileEndings: [String]) {
        self.folder = folder
        self.languageName = languageName
        self.codeFileEndings = codeFileEndings
    }
    
    public var folder: URL
    public let languageName: String
    public let codeFileEndings: [String]
}
