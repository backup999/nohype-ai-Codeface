import SwiftUI
import SwiftyToolz

struct FindAndFilterMenuOptions: View
{
    var body: some View
    {
        Button("Find and Filter")
        {
            withAnimation(.easeInOut(duration: Search.toggleAnimationDuration))
            {
                analysis?.set(searchBarIsVisible: true)
            }
        }
        .disabled(analysis == nil)
        .keyboardShortcut("f")

        Button("Toggle the Search Filter")
        {
            guard let analysis else
            {
                log(warning: "When there's no analysis, this menu option shouldn't be displayed.")
                return
            }
            
            withAnimation(.easeInOut(duration: Search.toggleAnimationDuration))
            {
                analysis.set(searchBarIsVisible: !analysis.search.barIsShown)
            }
        }
        .disabled(analysis == nil)
        .keyboardShortcut("f", modifiers: [.shift, .command])
    }
    
    private var analysis: CodebaseAnalysis?
    {
        codebaseProcessor.state.analysis
    }
    
    var codebaseProcessor: CodebaseProcessor
}
