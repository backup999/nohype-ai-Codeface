# TreeSitter PoC (structural / code tree)

## Status

**Largely done** as unit-test PoC. See [TreeSitter - How It Works.md](TreeSitter%20-%20How%20It%20Works.md) for model details and [Task - Integrate TreeSitter Analysis.md](Task%20-%20Integrate%20TreeSitter%20Analysis.md) for app integration.

## What it is

In-process TreeSitter → filtered **`CodeNode`** tree with early **declaration / reference** roles:

```text
CodeTreeGenerator.generateTree(from:language:)
  → uses SourceLanguage → grammar + LanguageProfile
  → [CodeNode]
```

| Type | Role |
|------|------|
| `CodeTreeGenerator` | Shared CST walk / projection |
| `CodeNode` / `CodeNode.Role` | Analysis IR node |
| `LanguageProfile` | Per-language rules, names, attributes, loose identifiers |
| `SourceLanguage` | `.swift` / `.python` + grammar binding |

Sources: `Code/TreeSitter PoC/` (app + test targets). Grammars: SwiftTreeSitter, TreeSitterSwift (`with-generated-files`), Vendor TreeSitterPython.

## Non-goals (PoC)

- App processor integration
- Dependency linking / AI
- Full language set
