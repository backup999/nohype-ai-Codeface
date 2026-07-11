import Observation

@MainActor
@Observable
final class GlobalSettings
{
    static let shared = GlobalSettings()
    
    private init() {}
    
    #if DEBUG
    var useCorrectAnimations = false
    #else
    /// DO NOT TOUCH THIS (so we can't accidentally fuck up a release)
    var useCorrectAnimations = false
    #endif
    
    #if DEBUG
    var updateSearchTermGlobally = true
    #else
    /// DO NOT TOUCH THIS (so we can't accidentally fuck up a release)
    var updateSearchTermGlobally = true
    #endif
    
    #if DEBUG
    var showPurchasePanel = false
    #else
    /// DO NOT TOUCH THIS (so we can't accidentally fuck up a release)
    var showPurchasePanel = true
    #endif
}
