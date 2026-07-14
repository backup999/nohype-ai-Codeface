# Task: Decouple Codebase Architecture from LSP types

## Goal

Make **`Code/App/Codebase Architecture/`** independent of SwiftLSP types, so that stage becomes the **first source-agnostic model**: same artifacts whether structure came from LSP or TreeSitter (+ later algorithms).

Today Architecture still depends on:

| Type | Used for |
|------|----------|
| `LSPDocumentSymbol.SymbolKind?` | `CodeSymbolArtifact.kind` → `kindName` + UI icons |
| `LSPRange` | symbol body/selection ranges → LOC, `contains`, code slice, line number, sort |

## Decisions (locked)

### Kind: free `String`, not a closed enum

- **Do not** re-create LSP’s 26-kind ontology as domain truth.
- Architecture stores a **display-oriented free string** (`kind: String`).
- The protocol already exposes `kindName: String`; keep that as the architecture surface.

**Producers:**

| Source | How `kind` is set |
|--------|-------------------|
| **LSP** | Use each symbol kind’s English name (`SymbolKind.name` → `"Class"`, `"Method"`, …). Already UI-ready; no humanization. |
| **TreeSitter** | Prefer refined tokens when the profile has them (e.g. Swift `declaration_kind` → `"struct"` / `"class"`). Else **language-agnostic humanize** of the grammar node type (`function_declaration` → `"Function"`, strip `_declaration` / `_definition` / …, title-case). |

Raw Tree-sitter node IDs stay in the TreeSitter IR (`CodeNode.kind`). They are **not** shown raw in UI unless unpaired with humanize.

Language-specific kind taxonomies / icon maps are **optional presentation later**, not required for Architecture.

### Range: own domain type

Introduce Architecture-owned range types (names TBD; suggested below), isomorphic enough to LSP positions that both backends map trivially:

```text
CodePosition { line: Int, character: Int }   // 0-based, same convention as LSP
CodeRange    { start: CodePosition, end: CodePosition }
```

Move range helpers needed by Architecture onto these types (`contains(_:)`, LOC span, etc.). Today `LSPRange.contains` is used when wiring dependency edges from reference locations.

### What stays LSP-shaped (out of this task’s core)

- **`CodeSymbol` / `.codebase` dump** (`LSP Codebase/`) may keep `LSPDocumentSymbol.SymbolKind` + `LSPRange` for format stability.
- Convert **once** at the boundary: `CodeSymbol` → `CodeSymbolArtifact` (and later: Structure IR / TreeSitter → artifact).
- No change required to on-disk `.codebase` schema for this task.

## Current dependency surface (inventory)

| Area | Files | Dependency |
|------|-------|------------|
| Artifact model | `Concrete Code Artifacts/CodeSymbolArtifact.swift` | `kind: SymbolKind?`, `range` / `selectionRange: LSPRange` |
| Conformance | `CodeSymbolArtifact+CodeArtifact.swift` | `kindNames` from LSP; range for `contains` / LOC / `lineNumber` |
| Create from codebase | `CodeSymbolArtifact+CodeSymbol.swift` | passes through LSP types; `getCode(of: LSPRange, …)`; `range.contains` vs reference ranges |
| Create from codebase | `CodeFileArtifact+CodeFile.swift` | sibling `range.contains` on references |
| Metrics | `GraphNode+Sorting.swift` | `selectionRange.start.line` |
| UI icons | `Artifact Icon/ArtifactIcon.swift` | switches on `SymbolKind` for image + color |
| UI wiring | `ArtifactViewModel.swift` | `icon = .for(symbolKind: symbolArtifact.kind)` |

After this task, **Architecture folder should have zero `import SwiftLSP`**. Analysis UI may still temporarily depend on string→icon maps that know LSP English names.

## Target shape

```text
LSP path                          TreeSitter path
   │                                     │
   ▼                                     ▼
CodeSymbol (may keep LSP types)    CodeNode (kind ID + attributes)
   │                                     │
   └──────────── adapter ────────────────┘
                     │
                     ▼
            CodeSymbolArtifact
            · kind: String
            · range / selectionRange: CodeRange
                     │
                     ▼
            CodeArtifact.kindName / metrics / graphs
                     │
                     ▼
            Presentation (icons keyed by free string)
```

Suggested domain placement:

- New small types under Architecture (e.g. `CodeRange.swift` next to `CodeArtifact.swift`) — **not** in `SwiftLSP`.

## Implementation phases

### Phase 1 — Introduce `CodeRange` / `CodePosition`

1. Add `CodePosition` + `CodeRange` (Equatable, Hashable, Sendable, Codable optional).
2. Port `contains(_:)` behavior from `LSPRange` (same 0-based line/character semantics).
3. Add LSPConversion helpers **outside** pure Architecture if needed, **or** convert only inside Create-from-Codebase so Architecture never imports SwiftLSP:
   - `LSPRange` → `CodeRange`
   - `LSPPosition` → `CodePosition`
4. Add simple unit-level checks if convenient (contains edge cases).

Stop: types exist; not yet wired everywhere.

### Phase 2 — `CodeSymbolArtifact` uses free kind + `CodeRange`

1. Change:

   ```swift
   let kind: String           // was LSPDocumentSymbol.SymbolKind?
   let range: CodeRange
   let selectionRange: CodeRange
   ```

2. `kindName` → `kind` (or empty / `"Unknown Kind of Symbol"` policy for missing; prefer non-optional `String` with a single unknown default at the adapter).
3. Drop Architecture’s `static var kindNames` unless a real UI consumer still needs a catalog — if kept, it becomes a UI-owned list of known labels, not `LSPDocumentSymbol.SymbolKind.names`.
4. Update `getCode(of:inFileLines:)` to take `CodeRange`.
5. In `CodeSymbolArtifact(symbol:…)`, map:
   - `kind: symbol.kind.name` (or handle optionality at boundary)
   - ranges via converter
6. Where reference locations are compared (`CodeSymbol.ReferenceLocation.range` still `LSPRange`), convert reference range to `CodeRange` for `contains` — **do not** pull LSP types back into the artifact model.
7. Confirm metrics/sort/`SearchableCodeArtifact.contains` compile against new fields.
8. Remove `import SwiftLSP` from Architecture sources. Create-from-Codebase may still import SwiftLSP **only if** it still talks to `CodeSymbol`; ideally confine conversion so only the LSP Codebase folder + a small mapper know SwiftLSP.

Stop: Architecture depends only on domain range + `String` kind; LSP route still builds artifacts; app builds.

### Phase 3 — Preserve current icons via UI string map

Without this step, specialized icons/colors are **lost** (enum switch no longer possible). Labels still show kind names.

1. Change `ArtifactIcon.for(…)` to accept `String?` / `String` (e.g. `for(symbolKindName:)`).
2. Re-express the current `switch symbolKind` as a **map keyed by the same English names** LSP already uses (`"Class"`, `"Method"`, `"Struct"`, …). Catalogs live in Analysis/UI, not Architecture.
3. Fallback for unmatched strings (TreeSitter humanized names later):
   - image: first letter + `.square.fill` (existing default path), or generic questionmark
   - color: secondary label or a small heuristic (optional later)
4. Wire `ArtifactViewModel` to pass `symbolArtifact.kind` (string).
5. Visual regression: open a known Swift/Dart project loaded via LSP — icons/colors should match pre-change for standard kinds.

Stop: LSP UX parity for icons; Architecture still free of LSP kinds.

### Phase 4 — TreeSitter display kind (when wiring TS → Architecture)

Deferred until a TreeSitter → artifact path exists (see [Integrate TreeSitter Analysis](Task%20-%20Integrate%20TreeSitter%20Analysis.md)), but **spec is decided**:

1. Adapter function, e.g. `displayKind(for node: CodeNode, language: …) -> String`:
   - if `attributes["declaration_kind"]` present → use that token (optionally title-cased for parity: `"struct"` → `"Struct"`)
   - else humanize `node.kind`
2. Humanize rules (language-agnostic, v0):
   - split on `_`
   - drop trailing noise tokens where useful: `declaration`, `definition`, `expression`, `statement` (tweak as real data shows awkward labels)
   - join remaining words Title Case
3. Do **not** harvest source keywords (`func` / `def` / `fun`) as architecture kinds.
4. Icons for TS kinds: fallback first; optional soft maps later (string catalogs), never required for independence.

Stop: TS-built architecture shows readable kind labels without a closed enum.

### Phase 5 — Optional cleanup

- Grep for residual `SwiftLSP` under Architecture / Analysis paths that no longer need it.
- If Analysis is fully string-based, document the icon catalog as the single place for “known gesture” of kind names.
- Align wording with Integrate TreeSitter task’s “unified domain model / no mandatory LSP types”.

## Relation to other tasks

| Task | Relation |
|------|----------|
| [Integrate TreeSitter Analysis](Task%20-%20Integrate%20TreeSitter%20Analysis.md) | Parent integration; this task **implements its Phase 5** early so Architecture is ready before a second backend is wired. Can land **independently** of processor reform. |
| [ProcessorPipelineArchitecture](Task%20-%20ProcessorPipelineArchitecture.md) | Orthogonal chassis; not a blocker for this decoupling. |
| TreeSitter PoC | Supplier of free-string kinds + attributes; humanize/refine lives at **adapter**, not inside PoC necessarily. |

Suggested order vs dual backends:

```text
[This task]  Architecture free of LSP SymbolKind + LSPRange
      │
      ▼
Structure IR / TreeSitter folder path can target Code*Artifact
without inventing a second artifact model
```

## Non-goals

- Changing `.codebase` / `CodeSymbol` Codable format.
- Building a cross-language SymbolKind enum or forcing 26-way TS → LSP mapping.
- Perfect per-language icon sets for TreeSitter.
- Full structure IR redesign (`StructureUnit` etc.) — only clear the Architecture type seam.
- Removing LSP retrieve path or SwiftLSP from the app.

## Definition of done

- [ ] `Code/App/Codebase Architecture/` has **no** `import SwiftLSP` and no references to `LSPRange` / `LSPDocumentSymbol.SymbolKind`
- [ ] `CodeSymbolArtifact` stores `kind: String` and domain `CodeRange`s
- [ ] LSP create path maps kind names + ranges at the boundary
- [ ] Icons for current LSP-backed projects preserve prior colors/symbols via string→icon map
- [ ] Unknown / TS-style kind strings have a safe generic icon fallback
- [ ] Humanize + `declaration_kind` preference documented for the future TS adapter (implemented when that path exists)
- [ ] Metrics, search-by-kindName, inspector labels, dependency scope checks still work

## Immediate next actions

1. Add `CodePosition` / `CodeRange` (+ `contains`).
2. Switch `CodeSymbolArtifact` + Create-from-Codebase mapping off LSP types.
3. String-based `ArtifactIcon` catalog using current LSP English names.
4. Build & manual smoke (LSP project icons + treemap).
5. Leave TS humanize helper stub or small pure function ready for the first TS→artifact mapper.
