# TreeSitter PoC (structural hierarchy)

## Context

Long-term: replace LSP with **TreeSitter** (structure) + dependency detection + small AI resolvers for false-positive-heavy edges.

This task: unit-test PoC only — **parse source with TreeSitter and extract a structural hierarchy** for **Swift and Python from day one**. Dual-language forces a multi-language API (no Swift-specialized core).

Sources live under `Code/TreeSitter PoC/` as normal Codeface app/test files (not a separate package). Wire them into the Xcode project manually (app target for implementation, test target for `HierarchyTests.swift`).

## Goal

1. Feed small Swift *and* Python snippets (types/classes + nested members).
2. Select grammar by language.
3. Parse → walk AST → hierarchy of named constructs (kind + name + range + children).
4. Assert expected nesting per language in unit tests.

## Frameworks (add in Xcode → app + tests)

| Package | Role |
|---------|------|
| [SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter) | Binding (`Parser`, `Tree`, `Node`) |
| [tree-sitter-swift](https://github.com/alex-pinkus/tree-sitter-swift) branch `with-generated-files` | Swift grammar (`TreeSitterSwift`) |
| Python grammar | Prefer **local** package `Code/TreeSitter PoC/Vendor/tree-sitter-python-src` (fixed `Package.swift`). Upstream remote often drops `scanner.c` (cwd `FileManager` bug) → linker errors on `tree_sitter_python_external_scanner_*` |

Link products: `SwiftTreeSitter`, `TreeSitterSwift`, `TreeSitterPython` to the targets that compile PoC sources/tests.

## Multi-language shape

```text
SourceLanguage          // .swift, .python
  → Language (grammar)

HierarchyExtractor      // shared parse + walk (stub returns [])
  → LanguageProfile     // next: per-language node/name rules

SymbolNode              // kind, name, children
```

## Target structure

```text
Code/TreeSitter PoC/
  SourceLanguage.swift
  SymbolNode.swift
  HierarchyExtractor.swift    // stub: parses, returns []
  HierarchyTests.swift        // Swift + Python; expect FAIL until walk is done
  Vendor/tree-sitter-python-src/   // local SPM package for fixed python grammar only
```

## Implementation steps

1. ~~Stub sources + packages wired in Xcode.~~
2. ~~Language profiles + AST walk (Swift + Python).~~
3. Confirm unit tests pass in Xcode.
4. Later: real processor integration.

## Out of scope

- Processor pipeline / UI replacement of LSP
- References / dependency algorithms / AI resolvers
- Languages beyond Swift + Python
