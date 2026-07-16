@MainActor
struct Search
{
    var barIsShown = false
    
    /// Layout/edit-session flag reported from the field's `@FocusState` (not a focus command).
    var fieldIsFocused = false
    
    /// Bumped to request keyboard focus on the search field (view-owned `@FocusState`).
    var fieldFocusGeneration = 0
    
    var term = ""
    
    static let toggleAnimationDuration: Double = 0.15
    static let layoutAnimationDuration: Double = 1.0
    static let filterUpdateAnimationDuration: Double = 0.15
}
