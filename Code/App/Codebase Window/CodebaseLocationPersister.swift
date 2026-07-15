import FoundationToolz
import Foundation

enum CodebaseLocationPersister
{
    static var hasPersistedLastCodebaseLocation: Bool { persistedCodebaseLocationData != nil }
    
    static func persist(_ location: CodebaseLocation) throws
    {
        let bookmarkData = try securityScopedBookmarkData(for: location.folder)
        
        let persistedLocation = PersistedCodebaseLocation(folderBookmarkData: bookmarkData,
                                                          codebaseLocation: location)
        
        persistedCodebaseLocationData = try persistedLocation.encode() as Data
    }
    
    static func loadCodebaseLocation() throws -> CodebaseLocation
    {
        guard let locationData = persistedCodebaseLocationData else
        {
            throw "Found no persisted codebase location"
        }
        
        var persistedLocation = try PersistedCodebaseLocation(jsonData: locationData)
        
        var bookMarkIsStale = false
        
        let folder = try URL(resolvingBookmarkData: persistedLocation.folderBookmarkData,
                             options: .withSecurityScope,
                             relativeTo: nil,
                             bookmarkDataIsStale: &bookMarkIsStale)
        
        persistedLocation.codebaseLocation.folder = folder
        
        if bookMarkIsStale
        {
            persistedLocation.folderBookmarkData = try securityScopedBookmarkData(for: folder)
            
            persistedCodebaseLocationData = try persistedLocation.encode() as Data
        }
        
        return persistedLocation.codebaseLocation
    }
    
    /// Create a security-scoped bookmark while holding access (required on modern macOS).
    private static func securityScopedBookmarkData(for folder: URL) throws -> Data
    {
        try folder.mapSecurityScoped
        {
            try $0.bookmarkData(options: .withSecurityScope,
                                includingResourceValuesForKeys: nil,
                                relativeTo: nil)
        }
    }
    
    // Computed so there is no global mutable static storage for the concurrency checker.
    private static var persistedCodebaseLocationData: Data?
    {
        get { UserDefaults.standard.object(forKey: storageKey) as? Data }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }
    
    private static let storageKey = "persistedCodebaseLocationData"
}

private struct PersistedCodebaseLocation: Codable
{
    var folderBookmarkData: Data
    var codebaseLocation: CodebaseLocation
}
