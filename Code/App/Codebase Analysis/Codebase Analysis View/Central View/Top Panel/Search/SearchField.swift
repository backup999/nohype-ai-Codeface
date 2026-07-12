import SwiftUI

struct SearchField: View
{
    var body: some View
    {
        HStack(alignment: .firstTextBaseline)
        {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search Field",
                      text: searchTermBinding,
                      prompt: Text("Find in \(artifactName)"))
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onChange(of: isFocused)
            {
                _, newFocus in
                
                withAnimation(.easeInOut(duration: Search.layoutAnimationDuration))
                {
                    analysis.set(fieldIsFocused: newFocus)
                }
            }
            .onChange(of: analysis.search.fieldFocusGeneration)
            {
                _, _ in
                // Programmatic focus request (e.g. ⌘F while the bar is already open).
                isFocused = true
            }
            .onChange(of: analysis.search.barIsShown)
            {
                _, shown in
                
                // Hiding the bar must resign focus so layout gets the unfocus trigger.
                if !shown { isFocused = false }
            }
            .onSubmit
            {
                isFocused = false
            }
            
            if !analysis.search.term.isEmpty
            {
                Button(systemImageName: "xmark.circle.fill")
                {
                    withAnimation(.easeInOut(duration: Search.layoutAnimationDuration))
                    {
                        analysis.set(searchTerm: "")
                    }
                }
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding([.leading, .trailing], 6)
        .frame(minWidth: 200, maxHeight: .infinity)
        .background
        {
            RoundedRectangle(cornerRadius: 6)
                .fill(.primary.opacity(isFocused ? 0.02 : 0.06))
        }
        .overlay
        {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.primary.opacity(0.2), lineWidth: 0.5)
        }
    }
    
    private var searchTermBinding: Binding<String>
    {
        Binding(
            get: { analysis.search.term },
            set: { newTerm in
                withAnimation(.easeInOut(duration: Search.filterUpdateAnimationDuration))
                {
                    analysis.set(searchTerm: newTerm)
                }
            }
        )
    }
    
    var analysis: CodebaseAnalysis
    
    @FocusState
    private var isFocused: Bool
    
    let artifactName: String
}

extension Button where Label == Image
{
    init(systemImageName: String, action: @escaping () -> Void)
    {
        self = Button(action: action)
        {
            Image(systemName: systemImageName)
        }
    }
}
