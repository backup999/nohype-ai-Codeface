import SwiftLSP
import Foundation
import SwiftyToolz

@MainActor
class CodebaseWindow: ObservableObject
{
    // MARK: - Initialize
    
    /// - Parameter onCodeFolderForDocument: Write savable `CodeFolder` into the FileDocument.
    ///   Called when the processor publishes a retrieved/loaded codebase (sync, MainActor).
    init(codebase: CodeFolder?,
         onCodeFolderForDocument: ((CodeFolder) -> Void)? = nil)
    {
        _lastLocation = Published(initialValue: try? CodebaseLocationPersister.loadCodebaseLocation())
        
        codebaseProcessor.onCodeFolderPublished = onCodeFolderForDocument
        
        if let codebase { runProcessor(with: codebase) }
    }
    
    // MARK: - Run Processor with Codebase at Location
    
    func runProcessorWithSwiftPackageCodebase(at folderURL: URL)
    {
        runProcessor(withCodebaseAtNewLocation: .init(folder: folderURL,
                                                        languageName: "Swift",
                                                        codeFileEndings: ["swift"]))
    }
    
    /// Product convenience: re-import the last folder when no analysis is loaded.
    /// Not wired into launch anymore — DocumentGroup owns open/restore first.
    /// Re-enable deliberately once the document baseline is solid.
    func runProcessorWithLastCodebaseIfNoneIsLoaded()
    {
        if CodebaseLocationPersister.hasPersistedLastCodebaseLocation
        {
            runProcessorWithLastCodebase()
        }
    }
    
    func runProcessorWithLastCodebase()
    {
        do
        {
            try runProcessor(withCodebaseAt: CodebaseLocationPersister.loadCodebaseLocation())
        }
        catch { log(error.readable) }
    }
    
    func runProcessor(withCodebaseAtNewLocation location: LSP.CodebaseLocation)
    {
        do
        {
            try runProcessor(withCodebaseAt: location)
            try CodebaseLocationPersister.persist(location)
        }
        catch { log(error.readable) }
    }
    
    private func runProcessor(withCodebaseAt location: LSP.CodebaseLocation) throws
    {
        guard FileManager.default.itemExists(location.folder) else
        {
            throw "Project folder does not exist: " + location.folder.absoluteString
        }
        
        runProcessor(from: .didLocateCodebase(location))
        lastLocation = location
    }
    
    @Published var lastLocation: LSP.CodebaseLocation?
    
    // MARK: - Load Processor for Codebase from File
    
    // TODO: make throwing instead of using optional try inside
    func runProcessor(withCodebaseAt fileURL: URL)
    {
        guard let fileData = try? Data(from: fileURL) else
        {
            log(error: "Couldn't read codebase file")
            return
        }
        
        guard let codebase = try? CodeFolder(jsonData: fileData) else
        {
            log(error: "Couldn't decode codebase")
            return
        }
        
        runProcessor(with: codebase)
    }
    
    func runProcessor(with codebase: CodeFolder)
    {
        runProcessor(from: .processCodebase(codebase,
                                            .init(primaryText: "Did Load Codebase Data",
                                                  secondaryText: "")))
    }
    
    // MARK: - Load Processor
    
    private func runProcessor(from state: CodebaseProcessorState)
    {
        codebaseProcessor.state = state
        codebaseProcessor.run()
    }
    
    // MARK: - Codebase Processor
    
    let codebaseProcessor = CodebaseProcessor()
    
    // MARK: - Import Views
    
    @Published var isPresentingCodebaseLocator = false
    @Published var isPresentingFolderImporter = false
    
    // MARK: - Display Options
    
    let displayOptions = WindowDisplayOptions()
}
