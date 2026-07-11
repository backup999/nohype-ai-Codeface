import SwiftUI

struct TreeMap: View
{
    var body: some View
    {        
        RootArtifactContentView(artifactVM: analysis.selectedArtifact,
                                analysis: analysis)
            .padding(ArtifactViewModel.padding)
            .background(Color(white: colorScheme == .dark ? 0 : 0.6))
    }
    
    var analysis: CodebaseAnalysis
    @Environment(\.colorScheme) var colorScheme
}
