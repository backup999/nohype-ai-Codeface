import SwiftUI
import SwiftyToolz

/// For Window Management On Launch. We have to use the app delegate, because onChange(of: scenePhase) does not work when no window is being opened on launch in the first place ... 🤮
@MainActor class CodefaceAppDelegate: NSObject, NSApplicationDelegate
{
    func applicationDidFinishLaunching(_ notification: Notification)
    {
        log(verbose: "Codeface did finish launching")
    }
    
    func applicationDidBecomeActive(_ notification: Notification)
    {
        log(verbose: "Codeface did become active")
        
        Task
        {
            // non-throwing so an unstructured Task doesn't silently drop errors
            try? await Task.sleep(for: .milliseconds(50))
            Self.openDocumentWindowIfNoneExist()
        }
    }
    
    func applicationWillUpdate(_ notification: Notification)
    {
        
//        log(verbose: "Codeface will update its windows")
//        log("number of windows: \(NSApp.windows.count)")
    }

    func applicationDidUpdate(_ notification: Notification)
    {
//        log(verbose: "Codeface did update its windows")
//        log("number of windows: \(NSApp.windows.count)")
    }
    
    func applicationDidResignActive(_ notification: Notification)
    {
        log(verbose: "Codeface did become inactive")
    }
    
    // MARK: - Window Management
    
    private static func openDocumentWindowIfNoneExist()
    {
        if !unidentifiedWindowsExist()
        {
            log(verbose: "🪟 gonna open document window because none exists")
            NSDocumentController.shared.newDocument(self)
        }
    }
    
    private static func unidentifiedWindowsExist() -> Bool
    {
        NSApp.windows.first { $0.identifier == nil } != nil
    }
}
