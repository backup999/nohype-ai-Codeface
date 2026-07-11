import SwiftUI

struct SearchField: View
{
    @MainActor
    init(analysis: CodebaseAnalysis, artifactName: String)
    {
        self.analysis = analysis
        _searchTerm = State(wrappedValue: analysis.search.term)
        self.artifactName = artifactName
    }
    
    var body: some View
    {
        HStack(alignment: .firstTextBaseline)
        {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search Field",
                      text: $searchTerm,
                      prompt: Text("Find in \(artifactName)"))
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onChange(of: isFocused)
            {
                // ❗️ we have to write the view model async (later) to not screw up focus management
                _, newFocus in
                
                Task
                {
                    withAnimation(.easeInOut(duration: 1))
                    {
                        analysis.set(fieldIsFocused: newFocus)
                    }
                }
            }
            .onChange(of: analysis.search.fieldIsFocused)
            {
                _, newFocus in
                isFocused = newFocus
            }
            .onChange(of: searchTerm)
            {
                // ❗️ we have to write the view model async (later) to not screw up focus management
                _, newTerm in
                
                Task
                {
                    withAnimation(.easeInOut(duration: Search.filterUpdateAnimationDuration))
                    {
                        analysis.set(searchTerm: newTerm)
                    }
                }
            }
            .onChange(of: analysis.search.term)
            {
                _, newTerm in
                searchTerm = newTerm
            }
            .onSubmit
            {
                // we don't wait for the view model here in order to avoid a certain visual hickup
                isFocused = false
                
                // ❗️ we have to write the view model async (later) to not screw up focus management
                Task
                {
                    withAnimation(.easeInOut(duration: Search.layoutAnimationDuration))
                    {
                        analysis.set(fieldIsFocused: false)
                    }
                }
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
    
    /// Keep analysis unowned by `@Observable` tracking of this view’s body so focus management stays independent of full re-observation patterns.
    let analysis: CodebaseAnalysis
    
    @FocusState
    private var isFocused: Bool
    
    @State
    private var searchTerm: String
    
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
