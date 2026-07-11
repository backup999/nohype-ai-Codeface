import SwiftUI

struct CodebaseAnalysisView: View
{
    var body: some View
    {
        NavigationSplitView(columnVisibility: $columnVisibility)
        {
            CodebaseNavigatorView(analysis: analysis,
                                  showsLinesOfCode: $displayOptions.showsLinesOfCode)
                .navigationSplitViewColumnWidth(min: 200,
                                                ideal: 300,
                                                max: 400)
                .listStyle(.sidebar)
        }
        detail:
        {
            CodebaseCentralView(analysis: analysis,
                                displayOptions: displayOptions)
        }
        .inspector(isPresented: $displayOptions.showsRightSidebar)
        {
            CodebaseInspectorView(selectedArtifact: analysis.selectedArtifact)
                .inspectorColumnWidth(min: 200,
                                      ideal: 250,
                                      max: 300)
        }
        .onChange(of: displayOptions.showsLeftSidebar)
        {
            _, showsLeftSidebar in
            
            withAnimation
            {
                columnVisibility = showsLeftSidebar ? .doubleColumn : .detailOnly
            }
        }
        .onChange(of: columnVisibility)
        {
            _, newValue in
            
            displayOptions.showsLeftSidebar = newValue == .all || newValue == .doubleColumn
        }
        .onAppear
        {
            columnVisibility = displayOptions.showsLeftSidebar ? .doubleColumn : .detailOnly
        }
    }
    
    var analysis: CodebaseAnalysis
    @Bindable var displayOptions: WindowDisplayOptions
    
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
}
