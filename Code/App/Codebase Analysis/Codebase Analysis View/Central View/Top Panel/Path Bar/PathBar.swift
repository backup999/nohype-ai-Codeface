import Combine

@MainActor
class PathBar: ObservableObject
{
    func select(_ artifactVM: ArtifactViewModel?)
    {
        artifactVMStack = artifactVM?.getPath() ?? []
    }

    func add(_ artifactVM: ArtifactViewModel)
    {
        remove(artifactVM)

        artifactVMStack.append(artifactVM)
    }

    func remove(_ artifactVM: ArtifactViewModel)
    {
        if let firstIndex = artifactVMStack.firstIndex(of: artifactVM)
        {
            let lastIndex = artifactVMStack.count - 1
            artifactVMStack.removeSubrange(firstIndex ... lastIndex)
        }
    }
    
    @Published private(set) var artifactVMStack = [ArtifactViewModel]()
}
