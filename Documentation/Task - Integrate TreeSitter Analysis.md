# Task: Integrate TreeSitter analysis (alongside / then past LSP)

## Context

Today’s pipeline is **LSP-shaped end-to-end**:

- retrieve: filesystem + **language server** symbols/refs → `CodeFolder` / `CodeFile` / `CodeSymbol` (SwiftLSP types woven in)
- architecture: `Code*Artifact` + graphs
- UI: `CodebaseAnalysis` / treemap

TreeSitter PoC delivers a second tech stack:

- parse grammars in-process → **`CodeNode` tree** via `CodeTreeGenerator` (filtered CST, free-string kinds, `declaration` | `reference`)
- later: name(± type)-based dep algorithms + AI resolvers

Challenge: **two analysis technologies** must meet the pipeline and the artifact model without a big-bang rewrite or a brittle dual fork forever.

Related:

- [Task - ProcessorPipelineArchitecture.md](Task%20-%20ProcessorPipelineArchitecture.md) — enum cases as sole store destroy earlier stage data
- [TreeSitter - How It Works.md](TreeSitter%20-%20How%20It%20Works.md) — grammars, profiles, program model
- [Task - TreeSitter PoC.md](Task%20-%20TreeSitter%20PoC.md) — PoC status (unit-test only so far)

## Decision: processor architecture **before** (or with) dual analysis

**Do processor pipeline reform first** (or as the immediate next thin vertical slice).

Why:

1. Dual tech needs **coexisting stage outputs** (`codeFolder` / program forest / deps / architecture / analysis). Enum-associated payloads **erase** ancestors and force awkward handoffs (already broken for document save vs visualization).
2. TreeSitter integration will add **new*** stages (parse → program trees → deps). Without durable fields, every new stage worsens the smell.
3. Reform is small and product-safe (no new panel semantics required); dual analysis is large.

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

1. **Stage data persists** once written (processor reform).
2. Structure/deps backends are **swappable providers** behind a source-agnostic model — not forever parallel `CodeSymbolLSP` vs `CodeSymbolTS` UI types.
3. LSP types (`LSPRange`, `SymbolKind`, …) move to **adapters at the boundary**, not deep into metrics/UI forever.
4. TreeSitter `CodeNode` is an **analysis IR**, not a permanent second document format. Saved `.codebase` can stay folder+text+(optional cache) for a long time.

## Recommended phases

### Phase 0 — Done baseline

- TreeSitter PoC: Swift + Python, role-tagged `CodeNode` / `CodeTreeGenerator`, profiles, tests.
- Document stack and dualism (decl/ref).

### Phase 1 — Processor coexisting stages (do next)

Execute [ProcessorPipelineArchitecture](Task%20-%20ProcessorPipelineArchitecture.md):

- durable: `location`, `codeFolder` (file tree + source text), later `structure`, `dependencies`, `architecture`, `analysis`
- phase enum shrinks to progress/error only
- document save tracks `codeFolder` continuously

This is the **integration chassis**. Without it, dual tech lands on sand.

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

## Ordering vs other tasks

| Task | Relation |
|------|----------|
| Processor coexisting stages | **Prerequisite chassis** |
| TreeSitter PoC | Input IR; keep available as library under `Code/TreeSitter PoC/` (evolve name later) |
| Flattened treemap | Orthogonal UI; ok after or in parallel once analysis VM still feeds frames |
| Dep algorithms + AI | After structure IR + TreeSitter folder path |

## Immediate next actions (when starting)

1. Implement processor durable stage fields (Phase 1).
2. Sketch `StructureUnit` / multi-file IR + adapters (Phase 2 design in code stubs + tests).
3. Folder-level TreeSitter extract → IR (no UI) tests.
4. Feature-flag backend switch → architecture for one language (Phase 3 slice).

## Success (integration, not PoC)

- [ ] Processor retains source + structure + analysis without enum erase
- [ ] Structure IR free of mandatory LSP types
- [ ] TreeSitter backend can produce hierarchy for at least Swift + Python folders
- [ ] One switch builds architecture/UI from that backend
- [ ] Path defined for deps (even if v0 is name-only) without new storage shape fight
