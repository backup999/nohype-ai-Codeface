import AppKit
import SwiftLSP
import Foundation
import UniformTypeIdentifiers
import SwiftyToolz

@MainActor
class CodebaseWindow: ObservableObject
{
    // MARK: - Initialize
    
    init()
    {
        _lastLocation = Published(initialValue: try? CodebaseLocationPersister.loadCodebaseLocation())
        
        // Nested @Observable processor does not drive this ObservableObject; refresh menus on cache publish.
        codebaseProcessor.onCodeFolderPublished = { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
    
    // MARK: - Run Processor with Codebase at Location
    
    func runProcessorWithSwiftPackageCodebase(at folderURL: URL)
    {
        runProcessor(withCodebaseAtNewLocation: .init(folder: folderURL,
                                                        languageName: "Swift",
                                                        codeFileEndings: ["swift"]))
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
    
    // MARK: - Import / Export Codebase File
    
    func importCodebaseFile(from fileURL: URL)
    {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
        
        do
        {
            let codebase = try CodebaseFileIO.loadCodeFolder(from: fileURL)
            runProcessor(with: codebase)
        }
        catch
        {
            log(error: "Couldn't import codebase file: \(error.readable.message)")
        }
    }
    
    func presentExportCodebaseFilePanel()
    {
        guard let codeFolder = codebaseProcessor.codeFolder else
        {
            log(warning: "No codebase data to export")
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.codebase]
        panel.nameFieldStringValue = (lastLocation?.folder.lastPathComponent ?? "Codebase") + ".codebase"
        
        guard panel.runModal() == .OK, let fileURL = panel.url else { return }
        
        do { try CodebaseFileIO.export(codeFolder, to: fileURL) }
        catch { log(error: "Couldn't export codebase file: \(error.readable.message)") }
    }
    
    // MARK: - Load Processor for Codebase from Memory
    
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
    @Published var isPresentingCodebaseFileImporter = false
    
    // MARK: - Display Options
    
    let displayOptions = WindowDisplayOptions()
}
