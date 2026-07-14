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
        
        // Same entry as classic open: location → run(structureSource:)
        treeSitterOpen.onLocationChosen = { [weak self] location in
            self?.runProcessor(withCodebaseAtNewLocation: location,
                               structureSource: .treesitter)
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
    
    func runProcessor(withCodebaseAtNewLocation location: LSP.CodebaseLocation,
                      structureSource: StructureSource = .lsp)
    {
        do
        {
            try runProcessor(withCodebaseAt: location, structureSource: structureSource)
            try CodebaseLocationPersister.persist(location)
        }
        catch { log(error.readable) }
    }
    
    private func runProcessor(withCodebaseAt location: LSP.CodebaseLocation,
                              structureSource: StructureSource = .lsp) throws
    {
        guard FileManager.default.itemExists(location.folder) else
        {
            throw "Project folder does not exist: " + location.folder.absoluteString
        }
        
        lastLocation = location
        codebaseProcessor.state = .didLocateCodebase(location)
        codebaseProcessor.run(structureSource: structureSource)
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
        codebaseProcessor.state = .processCodebase(codebase,
                                                   .init(primaryText: "Did Load Codebase Data",
                                                         secondaryText: ""))
        codebaseProcessor.run(structureSource: .lsp)
    }
    
    // MARK: - Codebase Processor
    
    let codebaseProcessor = CodebaseProcessor()
    
    /// Tree-sitter open menus/importers (presentation only; work is via `run(structureSource:)`).
    let treeSitterOpen = TreeSitterOpenController()
    
    // MARK: - Import Views
    
    @Published var isPresentingCodebaseLocator = false
    @Published var isPresentingFolderImporter = false
    @Published var isPresentingCodebaseFileImporter = false
    
    // MARK: - Display Options
    
    let displayOptions = WindowDisplayOptions()
}
