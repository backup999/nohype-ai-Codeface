# Task: Integrate TreeSitter analysis (alongside / then past LSP)

## Context

Today’s pipeline is **LSP-shaped end-to-end**:

- retrieve: filesystem + **language server** symbols/refs → `CodeFolder` / `CodeFile` / `CodeSymbol` (SwiftLSP types woven in)
- architecture: `Code*Artifact` + graphs
- UI: `CodebaseAnalysis` / treemap

App shell (done separately): **session window** (`WindowGroup`), not `DocumentGroup`. Dump I/O is **Import / Export Codebase File…** against a durable processor **`codeFolder` cache** — not a live `FileDocument`. See [Drop DocumentGroup Keep Codebase File](Done/Task%20-%20Drop%20DocumentGroup%20Keep%20Codebase%20File.md).

TreeSitter PoC delivers a second tech stack:

- parse grammars in-process → **`CodeNode` tree** via `CodeTreeGenerator` (filtered CST, free-string kinds, `declaration` | `reference`)
- later: name(± type)-based dep algorithms + AI resolvers

Challenge: **two analysis technologies** must meet the pipeline and the artifact model without a big-bang rewrite or a brittle dual fork forever.

Related:

- [Task - ProcessorPipelineArchitecture.md](Task%20-%20ProcessorPipelineArchitecture.md) — enum cases as sole store destroy earlier stage data (**minimal** `codeFolder` cache already done; full coexisting stages still open)
- [TreeSitter - How It Works.md](TreeSitter%20-%20How%20It%20Works.md) — grammars, profiles, program model
- [Task - TreeSitter PoC.md](Task%20-%20TreeSitter%20PoC.md) — PoC status (unit-test only so far)
- [Done: Drop DocumentGroup…](Done/Task%20-%20Drop%20DocumentGroup%20Keep%20Codebase%20File.md) — session + import/export; **do not** couple TreeSitter to that shell work

## Decision: processor architecture **before** (or with) dual analysis

**Do full processor pipeline reform first** (or as the immediate next thin vertical slice) — *beyond* the contingent `codeFolder` export cache.

Why:

1. Dual tech needs **coexisting stage outputs** (`codeFolder` / program forest / deps / architecture / analysis). Enum-associated payloads **erase** ancestors and force awkward handoffs. Export already needed a side-channel; structure IR will need proper siblings, not another one-off.
2. TreeSitter integration will add **new** stages (parse → program trees → deps). Without durable fields, every new stage worsens the smell.
3. Reform is small and product-safe (no new panel semantics required); dual analysis is large.
4. Shell/session migration is **already done** and must stay independent — TreeSitter must not reintroduce document-binding or change `.codebase` schema in this pass.

Do **not** wait for full TreeSitter parity before reform — reform is an enabler, not blocked by TreeSitter.

Ok to overlap: reform embeds *hooks* (`structureSource`, optional `programUnits`) so a second path can land cleanly.

## Target shape (conceptual)

```text
                     location
                        │
                        ▼
               ┌─ retrieve filesystem ─┐
               │   raw file tree + text  │  durable: sourceTree / codeFolder(text)
               └───────────┬────────────┘
                           │
           ┌───────────────┴────────────────┐
           ▼                                ▼
    structure path A                  structure path B (new)
    (LSP — status quo)                (TreeSitter CodeNode forest)
           │                                │
           └────────────┬───────────────────┘
                        ▼
               unified domain model
               (names, ranges, hierarchy, roles)
                        │
                        ▼
               dependency linking
               (heuristic ± types ± AI)
                        │
                        ▼
               architecture artifacts (graphs, metrics)
                        │
                        ▼
               analysis / UI view models
```

Principles:

1. **Stage data persists** once written (processor reform; `codeFolder` already demonstrates this for the dump).
2. Structure/deps backends are **swappable providers** behind a source-agnostic model — not forever parallel `CodeSymbolLSP` vs `CodeSymbolTS` UI types.
3. LSP types (`LSPRange`, `SymbolKind`, …) move to **adapters at the boundary**, not deep into metrics/UI forever.
4. TreeSitter `CodeNode` is an **analysis IR**, not a permanent second document format. Saved/exported `.codebase` can stay folder+text+(optional cache) for a long time — serialised from session **`codeFolder`** (export), not from a document binding.
5. Import codebase file vs import folder remain separate entry points; TreeSitter only affects the **structure path after** source text is available.

## Recommended phases

### Phase 0 — Done baseline

- TreeSitter PoC: Swift + Python, role-tagged `CodeNode` / `CodeTreeGenerator`, profiles, tests.
- Dualism (decl/ref) in PoCModel.
- **Session app + durable `codeFolder` + Import/Export codebase file** (DocumentGroup dropped). Full coexisting stages still open.

### Phase 1 — Processor coexisting stages (do next)

Execute [ProcessorPipelineArchitecture](Task%20-%20ProcessorPipelineArchitecture.md):

- durable: `location`, `codeFolder` (already present — keep/harden), later `structure`, `dependencies`, `architecture`, `analysis`
- phase enum shrinks to progress/error only
- **export / dump**: always from durable `codeFolder` (already the model); no document-save race

This is the **integration chassis**. Without the generalisation, dual tech lands on sand (even though export already works).

### Phase 2 — Source IR: text first, structure second

Clear split:

| Stage output | Content |
|--------------|---------|
| **Source tree** | `CodeFolder`-like: paths, file text (no LSP-required fields) |
| **Structure IR** | hierarchy + symbols + ranges + **roles** (decl/ref), backend-agnostic |
| **Dependencies** | edges between structure ids |
| **Architecture** | current `Code*Artifact` graphs (consumes structure+deps) |

Work:

- Inventory SwiftLSP surface on `CodeSymbol` / artifacts / view models.
- Introduce thin **StructureUnit** (name TBD) ≈ multi-file forest of program nodes (or mapper from current symbols). Include range, language, role when available.
- TreeSitter: folder walk + extension→`SourceLanguage` + `CodeTreeGenerator` per file → structure IR.
- LSP path: **adapter** existing symbols/refs → same IR (refs already more complete when server works).

Stop criterion: architecture builders can take **structure IR**, not raw LSP types.

### Phase 3 — Wire TreeSitter path behind a switch

- Processor / settings: `structureBackend: lsp | treesitter | …`
- TreeSitter path: no LSP server for structure (still may need location picker that is backend-agnostic).
- Start with **structure only** (outline for treemap); deps: reuse none / empty / heuristic v0.
- Validate on small Swift + Python fixtures in unit tests + one manual folder.

UI should light up something useful on Python without Python LSP — proof of dual tech value.

### Phase 4 — Dependency pipeline on structure IR

- Name-match refs→decls within/across file (scope heuristics).
- FP-heavy is expected; leave AI resolvers as optional later stage.
- Operators/overloads: post dualism (types/context) — do not block v0.
- Feed existing artifact edge construction from IR edges rather than LSP locations only.

### Phase 5 — Decouple UI/domain from SwiftLSP kinds

- `kindName` / icons: map free-string treesitter kinds + lightweight tables (or keep LSP kind when adapted).
- Remove hard `import SwiftLSP` from metrics/treemap where possible.
- Hospitality: LSP remains optional adapter until default backends flip.

### Phase 6 — Default flip & sunset

- Default TreeSitter (+ deps/AI) when quality is acceptable.
- LSP optional or removed; unsubscribe external server UX (`LSPServiceHint`, …).

## Do **not**

- Big-bang delete LSP before structure IR exists.
- Store full CST in `.codebase` by default.
- Build AI resolvers before a simple name linker exists.
- Premature umbrella “all languages” packaging; add languages as profiles justify.
- Touch session shell / reintroduce document APIs for TreeSitter.
- Shrink `.codebase` to a project pointer as part of dual backends (separate later product task).

## Ordering vs other tasks

| Task | Relation |
|------|----------|
| Drop DocumentGroup + durable `codeFolder` export | **Done** — shell + dump cache; frozen dump schema for now |
| Processor coexisting stages (full) | **Prerequisite chassis** for clean dual backends |
| TreeSitter PoC | Input IR; keep available as library under `Code/TreeSitter PoC/` (evolve name later) |
| Flattened treemap | Orthogonal UI; ok after or in parallel once analysis VM still feeds frames |
| Dep algorithms + AI | After structure IR + TreeSitter folder path |
| `.codebase` → project file | **Later**, after dual path proven; independent of analysis backend |

```text
[Done]  WindowGroup + import/export + durable CodeFolder cache
        │
        ▼
[Next]  Full processor coexisting stages (generalizes the cache pattern)
        │
        ▼
[Then]  TreeSitter structure path → switch → deps → default flip
        │
        ▼
[Later] .codebase → project file (path + settings) — optional product change
```

## Immediate next actions (when starting)

1. Implement full durable stage fields beyond `codeFolder` (Phase 1).
2. Sketch `StructureUnit` / multi-file IR + adapters (Phase 2 design in code stubs + tests).
3. Folder-level TreeSitter extract → IR (no UI) tests.
4. Feature-flag backend switch → architecture for one language (Phase 3 slice).

## Success (integration, not PoC)

- [ ] Processor retains source + structure + analysis without enum erase
- [ ] Structure IR free of mandatory LSP types
- [ ] TreeSitter backend can produce hierarchy for at least Swift + Python folders
- [ ] One switch builds architecture/UI from that backend
- [ ] Path defined for deps (even if v0 is name-only) without new storage shape fight
- [ ] Export still works after analysis from durable `codeFolder` (no regression to DocumentGroup-era assumptions)
