import FoundationToolz
import Foundation
import Observation
import SwiftLSP
import SwiftyToolz

@MainActor
@Observable
class CodebaseProcessor
{
    // MARK: - Run Processing
    
    func run(structureSource: StructureSource = .lsp)
    {
        self.structureSource = structureSource
        
        Task
        {
            guard let codebase = await retrieveCodebase() else { return }
            
            // Durable cache for Export — set *before* state advances into phases that
            // no longer embed CodeFolder (e.g. analyzeArchitecture).
            publishCodeFolder(codebase)
            
            // generate architecture
            state = .processCodebase(codebase, .init(primaryText: "Generating Codebase Architecture",
                                                     secondaryText: ""))
            
            let codebaseArchitecture: CodeFolderArtifact
            switch structureSource
            {
            case .lsp:
                codebaseArchitecture = await CodebaseProcessorSteps.generateArchitecture(from: codebase)
            case .treesitter:
                do
                {
                    let forest = try await CodebaseProcessorSteps.extractTreeSitterForest(from: codebase)
                    codebaseArchitecture = await CodebaseProcessorSteps
                        .generateArchitecture(fromTreeSitterForest: forest)
                }
                catch
                {
                    log(error.readable.message)
                    state = .didFail(error.readable.message)
                    return
                }
            }
            
            // calculate metrics
            state = .processArchitecture(codebase,
                                         codebaseArchitecture,
                                         .init(primaryText: "Calculating Codebase Architecture Metrics",
                                               secondaryText: ""))
            await codebaseArchitecture.calculateMetrics()
            
            // create view model
            state = .processArchitecture(codebase,
                                         codebaseArchitecture,
                                         .init(primaryText: "Generating Codebase Architecture View Models",
                                               secondaryText: ""))
            let architectureViewModel = await ArtifactViewModel(folderArtifact: codebaseArchitecture,
                                                                isPackage: codebase.looksLikeAPackage)
            architectureViewModel.addDependencies()
            
            state = .analyzeArchitecture(.init(rootArtifact: architectureViewModel))
        }
    }
    
    private func retrieveCodebase() async -> LSPCodeFolder?
    {
        switch state
        {
        case .didJustRetrieveCodebase(let codebase):
            return codebase
            
        case .didLocateCodebase(let codebaseLocation):
            state = .retrieveCodebase("Reading raw data from codebase folder")
            guard let codebaseWithoutSymbols = await readCodebaseFolder(from: codebaseLocation) else
            {
                return nil
            }
            
            if structureSource == .treesitter
            {
                state = .didJustRetrieveCodebase(codebaseWithoutSymbols)
                return codebaseWithoutSymbols
            }
            
            do
            {
                state = .retrieveCodebase("Connecting to LSP server")
                let server = try await LSP.ServerManager.shared.initializeServer(for: codebaseLocation)
                
                state = .retrieveCodebase("Retrieving symbols and their references from LSP server")
                
                let codebase = try await CodebaseProcessorSteps.retrieveSymbolsAndReferences(for: codebaseWithoutSymbols,
                                                                                             from: server,
                                                                                             codebaseRootFolder: codebaseLocation.folder)
                
                state = .didJustRetrieveCodebase(codebase)
                return codebase
            }
            catch
            {
                log(warning: "Cannot talk to LSP server: " + error.readable.message)
                LSP.ServerManager.shared.serverIsWorking = false
                
                state = .didJustRetrieveCodebase(codebaseWithoutSymbols)
                return codebaseWithoutSymbols
            }
            
        case .processCodebase(let codebase, _):
            return codebase
            
        case .processArchitecture(let codebase, _, _):
            return codebase
            
        default:
            log(error: "Processor can't retrieve codebase as it is in state \(state)")
            return nil
        }
    }
    
    private func readCodebaseFolder(from codebaseLocation: LSP.CodebaseLocation) async -> LSPCodeFolder?
    {
        do
        {
            return try await CodebaseProcessorSteps.readFolder(from: codebaseLocation)
        }
        catch
        {
            log(error.readable.message)
            state = .didFail(error.readable.message)
            return nil
        }
    }
    
    // MARK: - Durable CodeFolder (survives enum state transitions)
    
    /// Last successfully retrieved / loaded codebase for **Export Codebase File**.
    /// Independent of `state`, which drops associated values when the phase changes.
    private(set) var codeFolder: LSPCodeFolder?
    
    /// Notified synchronously whenever `codeFolder` is published (MainActor).
    var onCodeFolderPublished: ((LSPCodeFolder) -> Void)?
    
    private func publishCodeFolder(_ codebase: LSPCodeFolder)
    {
        codeFolder = codebase
        onCodeFolderPublished?(codebase)
    }
    
    // MARK: - State
    
    var state = CodebaseProcessorState.empty
    
    private var structureSource: StructureSource = .lsp
}
