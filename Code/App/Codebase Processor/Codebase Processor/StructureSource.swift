/// Which structure backend feeds Architecture creation (same product pipeline after).
enum StructureSource: Equatable, Sendable
{
    /// Language-server symbols/refs → `CodeFolder` dump → existing Create-from-Codebase.
    case lsp
    /// Tree-sitter forest → Create Architecture from TreeSitter (no dump symbols).
    case treesitter
}
