import Foundation
import SwiftyToolz

/// UI for Tree-sitter “Open … (new)” menus — only picks a location; shared `run(structureSource:)` does the rest.
@MainActor
final class TreeSitterOpenController: ObservableObject
{
    @Published var isPresentingCodebaseLocator = false
    @Published var isPresentingPackageFolderImporter = false
    
    var onLocationChosen: ((CodebaseLocation) -> Void)?
    
    func presentPackageFolderPicker()
    {
        isPresentingPackageFolderImporter = true
    }
    
    func presentCodebaseLocator()
    {
        isPresentingCodebaseLocator = true
    }
    
    func openSwiftPackage(at folderURL: URL)
    {
        open(location: .init(folder: folderURL,
                             languageName: "Swift",
                             codeFileEndings: ["swift"]))
    }
    
    func open(location: CodebaseLocation)
    {
        do
        {
            guard FileManager.default.itemExists(location.folder) else
            {
                let errorMessage = "Project folder does not exist: " + location.folder.absoluteString
                log(error: errorMessage)
                throw errorMessage
            }
            onLocationChosen?(location)
        }
        catch
        {
            log(error.readable)
        }
    }
}
