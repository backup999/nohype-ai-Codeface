import SwiftUIToolz
import SwiftUI
import SwiftLSP
import SwiftyToolz

@main
struct CodefaceApp: App
{
    init()
    {
        LogViewModel.shared.startObservingLog()
        
        /// we provide our own menu option for fullscreen because the one from SwiftUI disappears as soon as we interact with any views ... 🤮
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
    }
    
    var body: some Scene
    {
        // MARK: Document windows (primary scene)
        //
        // Baseline: let DocumentGroup + NSDocumentController own launch and file menus.
        // - Restored sessions reopen previous document windows when the system allows.
        // - Cold launch with nothing to restore → system Open panel (macOS document-app default).
        // - File → New / Open / Open Recent come from DocumentGroup (do not replace .newItem).
        //
        // Product conveniences (always open last codebase / always open empty welcome document)
        // are intentionally not implemented here; re-add them once this baseline is solid.
        
        DocumentGroup(newDocument: CodebaseFileDocument())
        {
            CodebaseWindowView(codebaseFile: $0.$document)
        }
        .commands
        {
            CommandGroup(replacing: .appInfo)
            {
                Button("About Codeface")
                {
                    openWindow(id: AboutPanel.id)
                }
            }
            
            CommandGroup(after: .appInfo)
            {
                if let focusedDocumentWindow
                {
                    PurchaseMenu(displayOptions: focusedDocumentWindow.displayOptions)
                }
            }
            
            CommandGroup(after: .toolbar)
            {
                if let focusedDocumentWindow
                {
                    FindAndFilterMenuOptions(codebaseProcessor: focusedDocumentWindow.codebaseProcessor)
                }
            }
            
            ToolbarCommands()
            
            CommandGroup(replacing: .undoRedo) {} // hide unused undo/redo
            
            CommandGroup(replacing: .sidebar)
            {
                if let documentWindow = focusedDocumentWindow
                {
                    ViewButtons(codebaseProcessor: documentWindow.codebaseProcessor,
                                displayOptions: documentWindow.displayOptions)
                    
                    Divider()
                }
                
                Toggle("Use Consistent Animations (Slower)",
                       isOn: $settings.useCorrectAnimations)
                    .help("Animating layout changes with visual consistency is slower in scopes that contain many lines of code. You might need to deactive this at higher levels of large codebases.")
                    .keyboardShortcut("a", modifiers: [.control])
                
                Button("Toggle Fullscreen")
                {
                    Task { NSApp.toggleFullscreen() }
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }

            CommandGroup(replacing: .help)
            {
                DocumentLink.lspService

                DocumentLink.wiki
                
                Divider()
                
                Button("Show Testing Dashboard")
                {
                    openWindow(id: TestingDashboard.id)
                }
            }
            
            // Keep system New / Open / Open Recent from DocumentGroup.
            // Only append Codeface-specific import actions.
            CommandGroup(after: .newItem)
            {
                Divider()
                
                Button("Import Code Folder...")
                {
                    focusedDocumentWindow?.isPresentingCodebaseLocator = true
                }
                .disabled(focusedDocumentWindow == nil)
                
                Button("Import Swift Package Folder...")
                {
                    focusedDocumentWindow?.isPresentingFolderImporter = true
                }
                .disabled(focusedDocumentWindow == nil)
                
                Button("Import \(lastFolderName) Again")
                {
                    focusedDocumentWindow?.runProcessorWithLastCodebase()
                }
                .keyboardShortcut("r")
                .disabled(focusedDocumentWindow == nil || !CodebaseLocationPersister.hasPersistedLastCodebaseLocation)
                
                Divider()
            }
        }
        
        // MARK: Auxiliary windows
        //
        // Opened only via openWindow(id:) / menu. They do not use
        // defaultLaunchBehavior(.presented). (`.suppressed` exists on macOS 15+;
        // deployment is still macOS 14, and the default is already non-presenting.)
        
        TestingDashboard()
        
        AboutPanel(privacyPolicyURL: .privacyPolicy,
                   licenseAgreementURL: .licenseAgreement)
    }
    
    private var lastFolderName: String
    {
        if let lastFolder = focusedDocumentWindow?.lastLocation?.folder
        {
            return "\"" + lastFolder.lastPathComponent + "\""
        }
        else
        {
            return "Last Folder"
        }
    }
    
    // MARK: - Basics
    
    @Bindable private var settings = GlobalSettings.shared
    @FocusedObject private var focusedDocumentWindow: CodebaseWindow?
    @Environment(\.openWindow) var openWindow
}
