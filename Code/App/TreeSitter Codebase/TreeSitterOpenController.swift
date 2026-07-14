import Foundation
import SwiftUI
import SwiftLSP
import SwiftyToolz

/// UI for Tree-sitter “Open … (new)” menus — only picks a location; shared `run(structureSource:)` does the rest.
@MainActor
final class TreeSitterOpenController: ObservableObject
{
    @Published var isPresentingCodebaseLocator = false
    @Published var isPresentingPackageFolderImporter = false
    
    var onLocationChosen: ((LSP.CodebaseLocation) -> Void)?
    
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
    
    func open(location: LSP.CodebaseLocation)
    {
        do
        {
            guard FileManager.default.itemExists(location.folder) else
            {
                throw "Project folder does not exist: " + location.folder.absoluteString
            }
            onLocationChosen?(location)
        }
        catch
        {
            log(error.readable)
        }
    }
}

// MARK: - SwiftUI surface

extension View
{
    func treeSitterOpenSources(_ controller: TreeSitterOpenController) -> some View
    {
        modifier(TreeSitterOpenViewModifier(controller: controller))
    }
}

private struct TreeSitterOpenViewModifier: ViewModifier
{
    @ObservedObject var controller: TreeSitterOpenController
    
    func body(content: Content) -> some View
    {
        content
            .fileImporter(isPresented: $controller.isPresentingPackageFolderImporter,
                          allowedContentTypes: [.directory],
                          allowsMultipleSelection: false)
            {
                guard let folderURL = (try? $0.get())?.first else
                {
                    return log(error: "Could not select code folder")
                }
                controller.openSwiftPackage(at: folderURL)
            }
            .sheet(isPresented: $controller.isPresentingCodebaseLocator)
            {
                CodebaseLocator(isBeingPresented: $controller.isPresentingCodebaseLocator)
                {
                    controller.open(location: $0)
                }
                .padding()
            }
    }
}
