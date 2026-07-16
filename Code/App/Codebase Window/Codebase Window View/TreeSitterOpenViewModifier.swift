import Foundation
import SwiftUI
import SwiftyToolz

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
    
    @ObservedObject var controller: TreeSitterOpenController
}

