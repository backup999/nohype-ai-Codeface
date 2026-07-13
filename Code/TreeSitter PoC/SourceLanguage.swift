import SwiftTreeSitter
import TreeSitterSwift
import TreeSitterPython

/// Supported source languages for the Tree-sitter PoC.
///
/// Binds each case to (1) a compiled grammar (`tree_sitter_*`) and (2) a
/// `LanguageProfile` that describes how that grammar’s CST projects into
/// `CodeNode`s. Adding a language ≈ package the grammar + write a profile.
enum SourceLanguage: String, Sendable {
    case swift
    case python

    /// Tree-sitter language object for `CodeTreeGenerator`’s shared `Parser`.
    var treeSitterLanguage: Language {
        switch self {
        case .swift:
            Language(language: tree_sitter_swift())
        case .python:
            Language(language: tree_sitter_python())
        }
    }

    /// Projection rules for this language (see `LanguageProfile`).
    var profile: LanguageProfile {
        switch self {
        case .swift: .swift
        case .python: .python
        }
    }
}
