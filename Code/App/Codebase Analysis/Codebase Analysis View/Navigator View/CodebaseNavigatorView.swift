import SwiftUI
import SwiftyToolz

struct CodebaseNavigatorView: View
{
    var body: some View
    {
        List([analysis.rootArtifact],
             children: \.children,
             selection: $analysis.selectedArtifactID)
        {
            artifact in

            NavigationLink(value: artifact.id)
            {
                SidebarLabel(artifactVM: artifact,
                             showsLinesOfCode: $showsLinesOfCode)
//                    .listRowBackground(nil)
            }
        }
    }
    
    @Bindable var analysis: CodebaseAnalysis
    
    // held separately so row content is not tightly coupled to other analysis state for LoC toggles
    @Binding var showsLinesOfCode: Bool
}

private extension ArtifactViewModel
{
    var children: [ArtifactViewModel]?
    {
        parts.isEmpty ? nil : parts
    }
}
