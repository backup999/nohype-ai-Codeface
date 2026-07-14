import SwiftUI
import SwiftLSP
import SwiftyToolz

struct CodebaseWindowView: View
{
    var body: some View
    {
        CodebaseProcessorView(codebaseProcessor: documentWindow.codebaseProcessor,
                              displayOptions: documentWindow.displayOptions)
            .focusedSceneObject(documentWindow)
            .fileImporter(isPresented: $documentWindow.isPresentingFolderImporter,
                          allowedContentTypes: [.directory],
                          allowsMultipleSelection: false)
            {
                guard let folderURL = (try? $0.get())?.first else
                {
                    return log(error: "Could not select code folder")
                }
                
                documentWindow.runProcessorWithSwiftPackageCodebase(at: folderURL)
            }
            .fileImporter(isPresented: $documentWindow.isPresentingCodebaseFileImporter,
                          allowedContentTypes: [.codebase],
                          allowsMultipleSelection: false)
            {
                guard let fileURL = (try? $0.get())?.first else
                {
                    return log(error: "Could not select codebase file")
                }
                
                documentWindow.importCodebaseFile(from: fileURL)
            }
            .sheet(isPresented: $documentWindow.isPresentingCodebaseLocator)
            {
                CodebaseLocator(isBeingPresented: $documentWindow.isPresentingCodebaseLocator)
                {
                    documentWindow.runProcessor(withCodebaseAtNewLocation: $0)
                }
                .padding()
            }
            .toolbar
            {
                ToolbarItemGroup(placement: .secondaryAction)
                {
                    SecondaryToolbarButtons(codebaseProcessor: documentWindow.codebaseProcessor)
                }
                
                ToolbarItemGroup(placement: .primaryAction)
                {
                    Spacer()
                    
                    PrimaryToolbarButtons(codebaseProcessor: documentWindow.codebaseProcessor,
                                          displayOptions: documentWindow.displayOptions)
                }
            }
    }
    
    @StateObject private var documentWindow = CodebaseWindow()
}
