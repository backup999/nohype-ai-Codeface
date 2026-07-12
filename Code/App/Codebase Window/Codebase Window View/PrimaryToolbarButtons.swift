import SwiftUI

struct PrimaryToolbarButtons: View
{
    var body: some View
    {
        if let analysis
        {
            Button(systemImageName: "magnifyingglass")
            {
                withAnimation(.easeInOut(duration: Search.toggleAnimationDuration))
                {
                    analysis.set(searchBarIsVisible: !analysis.search.barIsShown)
                }
            }
            .help("Toggle the Search Filter (⇧⌘F)")
            
            UpdatingDisplayModePicker(analysis: analysis)
            
            Button(systemImageName: "sidebar.right")
            {
                withAnimation
                {
                    displayOptions.showsRightSidebar.toggle()
                }
            }
            .help("Toggle Inspector (⌥⌘0)")
        }
    }
    
    private var analysis: CodebaseAnalysis?
    {
        codebaseProcessor.state.analysis
    }
    
    var codebaseProcessor: CodebaseProcessor
    var displayOptions: WindowDisplayOptions
}

struct UpdatingDisplayModePicker: View
{
    var body: some View
    {
        DisplayModePicker(displayMode: $analysis.displayMode)
    }
    
    @Bindable var analysis: CodebaseAnalysis
}
