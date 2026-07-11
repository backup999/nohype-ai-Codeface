import Observation

@MainActor
@Observable
final class WindowDisplayOptions
{
    var showsSubscriptionPanel = false
    var showsLeftSidebar = true
    var showsRightSidebar = false
    var showsLinesOfCode = false
}
