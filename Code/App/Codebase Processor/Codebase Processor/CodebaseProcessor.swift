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
            // retrieve raw codebase
            guard let codebase = await retrieveCodebase() else { return }
            
            // Durable cache for Export — set *before* state advances into phases that
            // no longer embed CodeFolder (e.g. analyzeArchitecture).
            if case let .lsp(lspCodebase) = codebase {
                publishCodeFolder(lspCodebase)
            }
            
            // generate architecture
            state = .processCodebase(codebase, .init(primaryText: "Generating Codebase Architecture",
                                                     secondaryText: ""))
            
            let codebaseArchitecture: CodeFolderArtifact
            
            switch codebase
            {
            case .lsp(let lspCodebase):
                codebaseArchitecture = await CodebaseProcessorSteps.generateArchitecture(
                    from: lspCodebase
                )
            case .treeSitter(let treeSitterCodebase):
                codebaseArchitecture = await CodebaseProcessorSteps.generateArchitecture(
                    fromTreeSitterForest: treeSitterCodebase
                )
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
                                                                isPackage: codebaseArchitecture.looksLikeAPackage)
            architectureViewModel.addDependencies()
            
            state = .analyzeArchitecture(.init(rootArtifact: architectureViewModel))
        }
    }
    
    private func retrieveCodebase() async -> CodebaseProcessorState.Codebase?
    {
        switch state
        {
        case .didJustRetrieveCodebase(let codebase):
            return codebase
            
        case .didLocateCodebase(let codebaseLocation):
            state = .retrieveCodebase("Reading raw data from codebase folder")
            
            switch structureSource {
            case .treesitter:
                do {
                    let treeSitterCodebase = try TreeSitterFolder.readFolder(from: codebaseLocation)
                    state = .didJustRetrieveCodebase(.treeSitter(treeSitterCodebase))
                    return .treeSitter(treeSitterCodebase)
                } catch {
                    log(error: "Could not load TreeSitter codebase: " + error.readable.message)
                    state = .didFail(error.readable.message)
                    return nil
                }
                
            case .lsp:
                guard let codebaseWithoutSymbols = await readCodebaseFolder(from: codebaseLocation) else
                {
                    return nil
                }
                
                do
                {
                    state = .retrieveCodebase("Connecting to LSP server")
                    let server = try await LSP.ServerManager.shared.initializeServer(for: codebaseLocation)
                    
                    state = .retrieveCodebase("Retrieving symbols and their references from LSP server")
                    
                    let codebase = try await CodebaseProcessorSteps.retrieveSymbolsAndReferences(for: codebaseWithoutSymbols,
                                                                                                 from: server,
                                                                                                 codebaseRootFolder: codebaseLocation.folder)
                    
                    state = .didJustRetrieveCodebase(.lsp(codebase))
                    return .lsp(codebase)
                }
                catch
                {
                    log(warning: "Cannot talk to LSP server: " + error.readable.message)
                    LSP.ServerManager.shared.serverIsWorking = false
                    
                    state = .didJustRetrieveCodebase(.lsp(codebaseWithoutSymbols))
                    return .lsp(codebaseWithoutSymbols)
                }
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
            log(error: error.readable.message)
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
