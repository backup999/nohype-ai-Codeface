# TreeSitter stack: how it works + multi-language scaling

## Mental model vs reality

| What people often mean by “grammar” | What the app actually runs |
|-------------------------------------|----------------------------|
| A declarative description of the language | A **generated C state machine** (`parser.c`, sometimes `scanner.c`) compiled into the binary |

**Authoring path** (grammar maintainers):

```text
grammar.js  --(tree-sitter CLI / Node)-->  parser.c (+ scanner.c) + headers
```

**App path** (Codeface):

```text
pre-generated .c sources  --(clang via Xcode/SPM)-->  linked lib exposing tree_sitter_<lang>()
                                                      ↑
                                              SwiftTreeSitter calls that
```

“Build the grammar” means **compile community-generated C into the app**, not invent the language. Everyone shares the same grammar sources for a language version; packaging for SPM/Xcode is the uneven bit.

## Dependencies

```text
CodeTreeGenerator + SourceLanguage + LanguageProfile
        │                   │                    │
        ▼                   ▼                    ▼
 SwiftTreeSitter     TreeSitterSwift      TreeSitterPython
 (Swift API)         (Swift grammar)      (Python grammar)
        │                   │                    │
        ▼                   └─────────┬──────────┘
   TreeSitter C runtime               tree_sitter_<lang>()
```

| Piece | Role |
|-------|------|
| TreeSitter + SwiftTreeSitter | One engine + one binding for all languages |
| Per-language package | Compiled grammar tables |
| Our PoC | Shared walk (`CodeTreeGenerator`) + per-language **profile** → `CodeNode` tree |

### Packaging notes

- **Swift grammar:** use branch `with-generated-files` (release tags often omit generated C).
- **Python:** local `Vendor/tree-sitter-python-src` fixes SPM that drops `scanner.c`; not a Codeface-specific grammar.
- Longer term: optional umbrella “Grammars” package; still compile C, not ship `grammar.js` at runtime.

## What a language profile is for

Tree-sitter already gives a full **CST hierarchy**. Profiles do **not** recreate nesting. They define the **projection** onto `CodeNode`:

| Profile answers | Example |
|-----------------|--------|
| Which CST node types to **keep** | `function_declaration`, `call`, … not `{` / `pass` |
| **Role** of each kept type | `.declaration` vs `.reference` (`CodeNode.Role`) |
| How to read **`name`** | field `"name"`, dig through patterns, callee extraction |
| Optional **attributes** | Swift `declaration_kind` → `"struct"` |
| Where bare **`identifier`s** count as refs | Python bases / import names only |

Kinds stay Tree-sitter-native free strings (no cross-language “Interface” ontology).

### `rules` vs `looseIdentifierFields`

```text
rules                         // type alone ⇒ CodeNode
  "call_expression" → reference
  "class_definition" → declaration
  …

looseIdentifierFields         // type alone is NOT enough
  class_definition.superclasses → bare identifier Bar is a reference
```

**Why both?**

- Many uses have a dedicated node type (`call_expression`, `user_type`) → belong in **`rules`**.
- Some grammars only put `identifier` (e.g. `class Foo(Bar)` base). Putting **all** `identifier`s in `rules` would also capture parameters, locals, loop vars → noise.
- **`looseIdentifierFields`** enables identifier→reference only under specific **parent type + field** paths.

Swift currently leaves `looseIdentifierFields` empty (types/calls covered by proper node types).

## Target model: `CodeNode` tree

**One filtered tree with analysis roles** (declared early for deps):

```text
full TreeSitter CST
        │  LanguageProfile
        ▼
CodeNode
  role:        declaration | reference   // CodeNode.Role
  kind:        treesitter node type
  name:        surface name
  attributes:  optional free-string fields
  children:    nested code nodes
```

API entry point: `CodeTreeGenerator.generateTree(from:language:)`.

- **Declarations** → structure / metrics / UI collapse.
- **References** (incl. inheritance, param types, not only leaf calls) → dependency fuel in the same walk.
- Name-only matching of ref→decl is a **first** edge heuristic; **overloads / operators** need argument/operand types (and maybe AI resolvers) later — not a reason to drop the dualism.

### Generator walk (shared)

1. Parse with grammar for `SourceLanguage`.
2. DFS: if node type ∈ `rules` and name readable → emit `CodeNode`.
3. **Declarations** open **all** CST children (no body-only cutoff). **References are leaves** — no nested code children — so nested CST shells (`inheritance_specifier` → `user_type` → same name) do not become two refs for one token.
4. Under loose fields, bare `identifier` may emit as `.reference`.
5. Everything else is skimmed (children only).

Why leaf refs: grammars stack several node types around one use; type-based selection alone double-counts unless the walk stops at the first reference shell (or the profile lists only the innermost type and never the outer).

## Scaling — work per language

1. Package grammar (SPM / vendor / umbrella target).
2. `SourceLanguage` case + `LanguageProfile` (rules + attributes + loose fields as needed).
3. Fixture tests: source → expected `CodeNode` tree (`CodeTreeGeneratorTests`).

No new runtime binding; no LSP per language for structure.

## App Store

Grammars compile into the binary. No user language servers, no runtime `grammar.js`.

## PoC checklist

- [x] Runtime + Swift binding + Swift/Python grammars
- [x] Role-tagged code tree (`CodeNode` / `CodeTreeGenerator`)
- [x] Profiles documented (`rules` vs loose identifiers)
- [x] Tests (inheritance/base, property/param types, calls)
- [ ] Overload / operator-aware linking (type context)
- [ ] More languages / umbrella grammars package
- [ ] Processor integration, dep algorithms, AI resolvers
