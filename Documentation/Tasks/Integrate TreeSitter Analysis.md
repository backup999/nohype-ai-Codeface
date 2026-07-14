# Task: Integrate TreeSitter analysis (alongside / then past LSP)

## Status (2026-07-14)

**Iteration 1 (structure only) is landed** as a dual menu path into the same processor pipeline. Full processor stage reform, deps linking, and default flip remain open.

| Area | Status |
|------|--------|
| Session shell + durable `codeFolder` export | **Done** (separate task) |
| Architecture free of `SymbolKind` / owns `CodeRange` | **Done** — [Decouple Architecture from LSP Types](Task%20-%20Decouple%20Architecture%20from%20LSP%20Types.md) |
| TreeSitter module (ex-PoC) under `Code/App/TreeSitter Codebase/` | **Done** (Vendor grammars stay in `Code/TreeSitter PoC/Vendor/`) |
| Shared `run(structureSource:)` + Architecture fork | **Done** |
| Menus **Open … (new)** → Tree-sitter structure | **Done** (hierarchy, empty deps) |
| Dependency detection on Tree-sitter IR | **Not started** |
| Full coexisting processor stages | **Still open** — [ProcessorPipelineArchitecture](Task%20-%20ProcessorPipelineArchitecture.md) |
| Default backend flip / sunset LSP | **Later** |

Related detail for iter 1: [TreeSitter Architecture Iteration 1 Structure Only](Task%20-%20TreeSitter%20Architecture%20Iteration%201%20Structure%20Only.md).

---

## Context

Product still has an **LSP-first** default path:

- retrieve: filesystem + **language server** symbols/refs → `CodeFolder` / `CodeFile` / `CodeSymbol`
- architecture: Create-from-Codebase → `Code*Artifact` + graphs (used-by → edges)
- UI: metrics / treemap / analysis VMs

**Second path (Tree-sitter)** shares the same control flow after location is chosen:

```text
Menu (classic)  →  locate  →  run(structureSource: .lsp)
Menu (new)      →  locate  →  run(structureSource: .treesitter)

run(structureSource):
  1. FS text (always); + LSP symbols/refs only if .lsp
  2. create Architecture   ← only real fork
  3. metrics + VMs + analysis state   ← shared
```

Tree-sitter does **not** fill dump `CodeSymbol`s. Paths stay independent below Architecture and merge at `CodeFolderArtifact`.

App shell: **session window** (`WindowGroup`); Import/Export `.codebase` from durable processor `codeFolder` cache. See [Drop DocumentGroup Keep Codebase File](Done/Task%20-%20Drop%20DocumentGroup%20Keep%20Codebase%20File.md).

---

## What landed (structure-only dual path)

### Layout

```text
Code/App/TreeSitter Codebase/
  CodeNode, CodeTreeGenerator, LanguageProfile, SourceLanguage
  TreeSitterFolder / TreeSitterFile
  Extract/TreeSitterCodebaseExtractor
  Create Architecture/Code*Artifact+TreeSitter*
  TreeSitterOpenController   // menus: present only, then run(.treesitter)

Code/TreeSitter PoC/Vendor/  // grammar packages only
```

### Control flow

| Piece | Role |
|--------|------|
| `StructureSource` | `.lsp` \| `.treesitter` |
| `CodebaseProcessor.run(structureSource:)` | intention stored; retrieve + Architecture switch |
| Retrieve | `.treesitter` → text-only `CodeFolder` (no language server) |
| Architecture | `.lsp` → existing Create-from-Codebase; `.treesitter` → forest → Create Architecture from TS |
| Post-Architecture | metrics / `ArtifactViewModel` / `state` — unchanged shared tail |
| Menus | **Open Code Folder (new)…** / **Open Swift Package Folder (new)…** → same locate shape as classic, then `run(.treesitter)` |

### Architecture model (source-agnostic)

- `CodeSymbolArtifact.kind: String` (display label; not `LSPDocumentSymbol.SymbolKind`)
- `CodeRange` / `CodePosition` domain types
- Icons: UI maps free strings (LSP English names when from LSP path)
- Tree-sitter kinds: `SymbolKindDisplay` (prefer `declaration_kind`, else humanize node type)

### Iteration 1 limits

- **Declarations only** in the Architecture tree (references stay in `CodeNode` IR for later linking)
- **Empty dependency graphs** (no used-by → edge wiring yet)
- Import `.codebase` dump still uses **LSP** Architecture factory (`structureSource: .lsp`)
- **Open … Again** still uses last location with **default `.lsp`**

### Principles kept

1. No mutual code between LSP Codebase and TreeSitter Codebase **below** Architecture (no synthetic `CodeSymbol` from TS).
2. Structure backends are producers of the **same** `Code*Artifact` types — not parallel UI models.
3. Tree-sitter `CodeNode` is analysis IR, not a second document format.
4. Export remains durable `codeFolder` (text tree); TS does not require changing `.codebase` schema.

---

## Target shape (still the north star)

```text
                     location
                        │
                        ▼
               ┌─ retrieve filesystem ─┐
               │   raw file tree + text  │  durable: codeFolder(text)
               └───────────┬────────────┘
                           │
           ┌───────────────┴────────────────┐
           ▼                                ▼
    structure path A                  structure path B
    (LSP symbols/refs)                (TreeSitter CodeNode forest)
           │                                │
           └────────────┬───────────────────┘
                        ▼
               Architecture (Code*Artifact graphs)
                        │
                        ▼
               dependency edges (later: shared wiring / name linker)
                        │
                        ▼
               metrics / analysis / UI
```

**Today:** both structure paths feed Architecture; TS edges empty.  
**Next:** produce used-by locations (or edges) from refs→decls and **reuse** existing Create-from-Codebase scope aggregation (or extract shared graph builder).

---

## Remaining phases

### Phase A — Processor coexisting stages (still recommended)

[ProcessorPipelineArchitecture](Task%20-%20ProcessorPipelineArchitecture.md): durable siblings for structure / deps / architecture / analysis; phase enum as progress only.

Dual path **already works** without full reform; reform still helps (no enum erase, durable forest, cleaner re-link).

### Phase B — Dependencies on Tree-sitter IR

- Name-match refs→decls (scope heuristics); AI later optional.
- Prefer fuel shaped like existing used-by lists so Architecture edge wiring can be reused.
- Feed artifact graphs; do not invent a second treemap model.

### Phase C — Product polish

- Optional: remember last `structureSource` for **Open Again**.
- Richer kind→icon maps for humanized TS labels.
- More languages = more `LanguageProfile`s + grammars.

### Phase D — Default flip & sunset

- Default TreeSitter when quality acceptable.
- LSP optional or removed; retire `LSPServiceHint` etc. when ready.

---

## Do **not**

- Big-bang delete LSP before deps quality is acceptable.
- Force TS through dump `CodeSymbol` / change `.codebase` schema for structure.
- Store full CST in `.codebase` by default.
- Build AI resolvers before a simple name linker.
- Premature “all languages” packaging.
- Reintroduce document APIs for TreeSitter.
- Put structure-backend forks in menus/UI beyond choosing `StructureSource`.

---

## Ordering vs other tasks

| Task | Relation |
|------|----------|
| Drop DocumentGroup + durable `codeFolder` | **Done** |
| Decouple Architecture from LSP types | **Done** (enabler) |
| TreeSitter Architecture Iteration 1 | **Done** (structure-only dual path) |
| Processor coexisting stages (full) | **Open** — chassis for durable forest/deps |
| Dep algorithms + AI | **Next product value** on TS path |
| Flattened treemap | Orthogonal UI |
| `.codebase` → project file | **Later** |

```text
[Done]  WindowGroup + import/export + codeFolder cache
[Done]  Architecture LSP-agnostic (kind String, CodeRange)
[Done]  TreeSitter Codebase + run(structureSource:) structure-only path
        │
        ▼
[Next]  Deps on TS IR (+ optional processor stage reform)
        │
        ▼
[Later] Default flip / LSP sunset / project file
```

---

## Immediate next actions

1. Design used-by / edge production from `CodeNode` references (iter 2).
2. Prefer reusing Architecture sibling-containment wiring with that fuel.
3. Optionally harden processor durable stages if forest must survive re-analysis.
4. Manual smoke: **Open Swift Package Folder (new)…** on a small Swift tree (hierarchy, no arrows).

---

## Success checklist

### Iteration 1 (structure only) — done

- [x] TreeSitter module produces multi-file forest (Swift + Python profiles)
- [x] Architecture from Tree-sitter without mutating LSP dump types
- [x] Shared `run(structureSource:)` with fork only at retrieve + Architecture create
- [x] Menus open TS path; metrics/UI consume same artifacts
- [x] Export still from durable `codeFolder` (text tree)
- [x] Unit tests for generator + Architecture conversion

### Integration (full)

- [ ] Processor retains source + structure + analysis without enum erase (full reform)
- [ ] TreeSitter path produces useful dependency graphs (not only hierarchy)
- [ ] Clear path for deps quality (name-only v0 → better later)
- [ ] Optional default flip when ready
