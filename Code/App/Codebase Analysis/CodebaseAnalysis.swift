import Observation

@MainActor
@Observable
class CodebaseAnalysis
{
    init(rootArtifact: ArtifactViewModel)
    {
        self.rootArtifact = rootArtifact
        self.selectedArtifact = rootArtifact
        pathBar.select(rootArtifact)
    }
    
    // MARK: - Search
    
    func set(searchBarIsVisible: Bool)
    {
        search.barIsShown = searchBarIsVisible
        
        // Keyboard focus is owned by the field's `@FocusState`. Request it when showing the bar
        // (including when the bar is already open, e.g. ⌘F to refocus).
        if searchBarIsVisible
        {
            search.fieldFocusGeneration += 1
        }
    }
    
    /// Called from the search field when `@FocusState` changes. One-shot layout/filter side effects.
    func set(fieldIsFocused: Bool)
    {
        guard search.fieldIsFocused != fieldIsFocused else { return }
        search.fieldIsFocused = fieldIsFocused
        if !fieldIsFocused { updateSearchFilter() }
        selectedArtifact.updateLayout(applySearchFilter: !fieldIsFocused)
    }
    
    func set(searchTerm: String)
    {
        guard search.term != searchTerm else { return }
        search.term = searchTerm // only for connecting to search text field UI ...
        updateSearchFilter() // update the filter synchronously, updates `passesSearchFilter` ...
        
        let didClearSearchTermViaButton = searchTerm.isEmpty && !search.fieldIsFocused
        
        if didClearSearchTermViaButton
        {
            selectedArtifact.updateLayout(applySearchFilter: false)
        }
    }
    
    private func updateSearchFilter()
    {
        if GlobalSettings.shared.updateSearchTermGlobally
        {
            // TODO: rather "clear search results" when term is empty
            rootArtifact.updateSearchResults(withSearchTerm: search.term)
            
            rootArtifact.updateSearchFilter(allPass: search.term.isEmpty)
        }
        else
        {
            // TODO: rather "clear search results" when term is empty
            selectedArtifact.updateSearchResults(withSearchTerm: search.term)
            
            selectedArtifact.updateSearchFilter(allPass: search.term.isEmpty)
        }
    }
    
    var search = Search()
    
    // MARK: - Path Bar
    
    let pathBar = PathBar()
    
    // MARK: - Artifact View Models
    
    let rootArtifact: ArtifactViewModel
    
    /// List selection source of truth (stable plain ID). Resolved to `selectedArtifact` on set.
    var selectedArtifactID: CodeArtifact.ID
    {
        get { selectedArtifact.id }
        set
        {
            guard newValue != selectedArtifact.id,
                  let found = rootArtifact.findArtifact(withID: newValue)
            else { return }
            
            selectedArtifact = found
            pathBar.select(found)
        }
    }
    
    // Observers of CodebaseAnalysis update when this is replaced; nested ArtifactViewModel changes are observed separately via that object.
    private(set) var selectedArtifact: ArtifactViewModel
    
    // MARK: - Display Mode
    
    func switchDisplayMode()
    {
        switch displayMode
        {
        case .code: displayMode = .treeMap
        case .treeMap: displayMode = .code
        }
    }
    
    var displayMode: DisplayMode = .treeMap
}

private extension ArtifactViewModel
{
    func findArtifact(withID id: CodeArtifact.ID) -> ArtifactViewModel?
    {
        if self.id == id { return self }
        
        for part in parts
        {
            if let found = part.findArtifact(withID: id) { return found }
        }
        
        return nil
    }
}
