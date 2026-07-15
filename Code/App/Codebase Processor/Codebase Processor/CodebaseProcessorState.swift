enum CodebaseProcessorState
{
    var analysis: CodebaseAnalysis?
    {
        if case .analyzeArchitecture(let analysis) = self { return analysis }
        return nil
    }
    
    case empty,
         didLocateCodebase(CodebaseLocation),
         retrieveCodebase(String),
         didJustRetrieveCodebase(Codebase),
         processCodebase(Codebase, ProgressFeedback),
         processArchitecture(Codebase, CodeFolderArtifact, ProgressFeedback),
         analyzeArchitecture(CodebaseAnalysis),
         didFail(String)
    
    enum Codebase {
        case treeSitter(TreeSitterFolder)
        case lsp(LSPCodeFolder)
    }
    
    struct ProgressFeedback
    {
        let primaryText: String
        let secondaryText: String
    }
}
