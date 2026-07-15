# Task: Integrate TreeSitter analysis (alongside / then past LSP)

## Status (2026-07-15)

**Iteration 2 (deps v0) is landed**: scope-stack name linker fills used-by on Tree-sitter declarations; Architecture already turns those into edges. Quality is expected to be rough (many misses / false positives). Full processor stage reform and default flip remain open.

| Area | Status |
|------|--------|
| Session shell + durable `codeFolder` export | **Done** (separate task) |
| Architecture free of `SymbolKind` / owns `CodeRange` | **Done** — [Decouple Architecture from LSP Types](Task%20-%20Decouple%20Architecture%20from%20LSP%20Types.md) |
| TreeSitter module under `Code/App/TreeSitter Codebase/` | **Done** |
| Shared `run(structureSource:)` + Architecture fork | **Done** |
| Menus **Open … (new)** → Tree-sitter structure | **Done** |
| Dependency detection on Tree-sitter IR | **Done (v0)** — `TreeSitterReferenceLinker` + wired before Architecture |
| Full coexisting processor stages | **Still open** — [ProcessorPipelineArchitecture](Task%20-%20ProcessorPipelineArchitecture.md) |
| Default backend flip / sunset LSP | **Later** |

Related detail for iter 1: [TreeSitter Architecture Iteration 1 Structure Only](Done/Task%20-%20TreeSitter%20Architecture%20Iteration%201%20Structure%20Only.md).

---

## Context

Product still has an **LSP-first** default path:

- retrieve: filesystem + **language server** symbols/refs → `LSPCodeFolder` / `LSPCodeFile` / `LSPCodeSymbol`
- architecture: Create-from-Codebase → `Code*Artifact` + graphs (used-by → edges)
- UI: metrics / treemap / analysis VMs

**Second path (Tree-sitter)** shares the same control flow after location is chosen:

```text
Menu (classic)  →  locate  →  run(structureSource: .lsp)
Menu (new)      →  locate  →  run(structureSource: .treesitter)

run(structureSource):
  1. FS + structure IR
     · .lsp         → LSP symbols + refs
     · .treesitter  → TreeSitterFolder (parse + role-tagged symbols)
  2. [TS only, next] link refs→decls → fill used-by on declarations
  3. create Architecture   ← only real fork (already dual factories)
  4. metrics + VMs + analysis state   ← shared
```

Tree-sitter does **not** fill dump `LSPCodeSymbol`s. Paths stay independent below Architecture and merge at `CodeFolderArtifact`.

App shell: **session window** (`WindowGroup`); Import/Export `.codebase` from durable processor `codeFolder` cache.

---

## What landed (structure-only dual path)

### Layout

```text
Code/App/TreeSitter Codebase/
  TreeSitterCodeSymbol, TreeSitterFile, TreeSitterFolder
  Language Support/ (LanguageProfile, SourceLanguage)
  Load/ (CodeTreeGenerator, TreeSitterFolder+File System, tests)

Code/App/Codebase Architecture/Create from TreeSitter Codebase/
  Code*Artifact+TreeSitter*   // mirror of LSP Create; already reads symbol.references
```

### Control flow

| Piece | Role |
|--------|------|
| `StructureSource` | `.lsp` \| `.treesitter` |
| `CodebaseProcessor.run(structureSource:)` | intention stored; retrieve + Architecture switch |
| Retrieve | `.treesitter` → `TreeSitterFolder` (text + parse); `.lsp` → LSP dump |
| Architecture | dual factories; both bubble used-by → sibling edges |
| Post-Architecture | metrics / `ArtifactViewModel` / `state` — unchanged shared tail |
| Menus | **Open Code Folder (new)…** / **Open Swift Package Folder (new)…** → `run(.treesitter)` |

### IR ready for deps (important)

`TreeSitterCodeSymbol` already has:

- `role: .declaration | .reference` — early tag from `LanguageProfile` / generator
- `references: [ReferenceLocation]?` — **used-by** list (same shape as LSP: path relative to root + `CodeRange`)
- reference-role nodes in the tree are **fuel** (call sites, type mentions, inheritance, imports, …)

Architecture Create-from-TreeSitter **already** consumes `symbol.references` exactly like the LSP path (sibling containment + bubble-up of out-of-scope refs). With empty/nil lists → empty graphs (current behaviour).

### Iteration 1 limits (still true until linker lands)

- Generator fills **structure + role tags**; no used-by lists yet
- **Empty dependency graphs** on TS path
- Import `.codebase` dump still uses **LSP** Architecture factory
- **Open … Again** still defaults to `.lsp`

### Principles kept

1. No mutual code between LSP Codebase and TreeSitter Codebase **below** Architecture.
2. Structure backends produce the **same** `Code*Artifact` types — not parallel UI models.
3. Tree-sitter forest is analysis IR, not a second document format.
4. Export remains durable `codeFolder` (text tree); TS does not require changing `.codebase` schema.
5. Prefer **used-by fuel** shaped like LSP so Architecture edge wiring stays reused.

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
    (LSP symbols + used-by)           (TreeSitterFolder + roles)
           │                                │
           │                                ▼
           │                      name/scope linker (iter 2)
           │                      refs → decls → used-by on decls
           │                                │
           └────────────┬───────────────────┘
                        ▼
               Architecture (Code*Artifact graphs)
                        │
                        ▼
               metrics / analysis / UI
```

**Today:** both structure paths feed Architecture; TS used-by empty → no edges.  
**Next:** fill used-by on declaration nodes; Architecture wiring already there.

---

## Phase B — Dependencies on Tree-sitter IR (immediate)

### Mental model (correct framing)

> Take a `TreeSitterFolder` forest and produce a **copy** (or rebuilt tree) where **declaration** `TreeSitterCodeSymbol`s have `references` filled with likely used-by locations.

Corrections / precision:

| Claim | Reality |
|--------|---------|
| “Add references on nodes” | Yes — but on **declarations**, as **used-by** lists (who points at me), not on reference-role nodes |
| Reference-role nodes | Stay as **sites** (name + range + file path); they are inputs to the linker, not recipients of the list |
| “Copy of the folder” | Accurate: `references` is `let`; rebuild symbols with filled lists (or a dedicated linker returning a new forest) |
| After linking | Existing `CodebaseProcessorSteps.generateArchitecture(from: TreeSitterFolder)` should produce edges with little/no change |

### Algorithm v0 — scope-stack name resolution (**chosen**)

**Decision:** walk the forest **downward** (DFS) with a **stack of environments** `name → declaration`. Do **not** climb from each ref and do **not** use a global name index.

This is the idiomatic compiler pass for “resolve uses to bindings.” Most-local match = top of stack wins.

#### What we use from each node

| Field | Role in v0 |
|--------|------------|
| `role` | `.declaration` = binding; `.reference` = use to resolve |
| `name` | exact string key for register / lookup |
| tree parent/children | nested **scopes** (folder → file → decl bodies) |
| `range` + file path | only to **record** used-by after a hit |

No types, signatures, or attributes in v0.

#### Scope model

```text
codebase root                    ← one shared root scope (cross-file top-level names)
  └─ folder*
       └─ file*                  ← push file scope
            └─ declaration*      ← push nested scope for body
                 └─ declaration* | reference*   (refs are leaves)
```

#### Pass (implement exactly this shape)

```text
input:  TreeSitterFolder  (roles set; references empty)
output: same shape; matched declarations carry used-by ReferenceLocations

// During walk: side table  declID → [ReferenceLocation]
// After walk:  rebuild forest attaching lists (references is let)

stack: [Scope]   // each Scope = Map<String, DeclID>
usedBy: Map<DeclID, [ReferenceLocation]>

resolve(folder):
  push empty scope                    // root / codebase scope
  registerTopLevelDecls(folder)       // all file-level decls under this tree into root
  walkFiles(folder)                   // resolve refs with stack; nested decl scopes
  pop

// Optional split for clarity:
// 1) first full pass only registers top-level decls into root (so cross-file works)
// 2) second pass walks files with stack: root already filled, push file scope, …

// —— per file ——

resolveFile(file, path):
  push empty scope                    // file scope (optional if all file-level
                                      // decls live only in root; v0: file scope
                                      // for nested-only, root holds file-level)
  // Simpler v0 (recommended):
  //   root already has all file-level decls from every file
  //   file does NOT push its own map for top-level names
  //   only nested declaration bodies push scopes
  process(file.symbols, path)
  // no pop if no file scope pushed

// —— core of a nested declaration body ——

// When entering a .declaration node that has children:
enterDeclBody(decl):
  push empty scope
  registerDeclarations(decl.children)   // local bindings first
  process(decl.children, path)
  pop

registerDeclarations(nodes):
  for n in nodes where n.role == .declaration:
    topScope[n.name] = id(n)          // v0: last-wins if duplicate in same scope

process(nodes, path):
  for n in nodes:
    switch n.role:
      case .reference:
        if let declID = lookup(n.name):
          usedBy[declID] += ReferenceLocation(path, n.range)
        // unresolved → ignore
      case .declaration:
        enterDeclBody(n)              // always push for body, even if no children

lookup(name):
  for scope in stack from top to bottom:
    if let d = scope[name]: return d
  return nil
```

**Recommended v0 scoping detail (keep simple):**

1. **Root scope:** register every **file-level** `.declaration` across the whole `TreeSitterFolder` (one pre-pass or register-as-you-load). Enables cross-file unique names.
2. **Nested scopes only** under declaration bodies (types, functions, …): register that body’s child declarations, then process.
3. **No separate file scope map** unless we later want file-private names; root + nested is enough for first arrows.
4. Duplicate names in **one** scope → last-wins. Same name in root from **two files** → last-wins is wrong; **v0: if name already in root, leave previous and do not overwrite** (or skip both for that name). Prefer: **first registration wins; second duplicate at root is ignored** so at least one stable target exists—or **skip resolving that name entirely** when count > 1. **Chosen: root names with >1 decl → never bind that name (ambiguous).** Nested scopes: last-wins is fine.

#### Why two-phase per scope (register then process)

```text
func a() { b() }
func b() { a() }
```

Register all sibling decls in the scope **before** resolving any refs / entering bodies. Otherwise source order breaks mutual references.

#### Output

- Walk only **mutates** `usedBy` side table (and temporary stack).
- Final step: map tree → new `TreeSitterFolder` with `references` filled on declarations that got hits.
- Architecture Create unchanged: already turns used-by into edges.

#### Explicitly out of v0

- Walk-up-from-ref, global best-candidate index  
- Overloads, types, imports/modules, access control, AI

### Placement in the app

```text
TreeSitterFolder.readFolder / load
        │
        ▼
  [NEW] TreeSitterFolder.withLinkedReferences()   // or free function / Linker type
        │  pure: forest → forest
        ▼
generateArchitecture(from: linkedForest)         // already exists
```

- Keep linker **inside TreeSitter Codebase** (or a thin sibling), not inside Architecture.
- Do **not** invent a second edge model; Architecture remains the graph owner.
- Optional later: cache linked forest only if processor durable stages land — not required for v0.

### Architecture hygiene

Create-from-TreeSitter walks **all** symbol children (declarations **and** references). Richer Tree-sitter IR in the artifact tree is intentional vs LSP outline-only. Reference nodes also remain linker fuel (used-by on declarations → edges).

### Tests (minimal)

1. Unit: small multi-symbol source → expected used-by on decls (same-file call + type mention).
2. Unit: multi-file → cross-file used-by path strings relative to root.
3. Architecture: after link, sibling edge appears (e.g. `bar` calls `qux` → edge when both are siblings under same parent).
4. Keep structural generator tests (no refs required).

### Non-goals for v0

- AI resolvers, overload/operator typing
- Perfect Swift/Python name resolution
- Changing `.codebase` schema or caching deps in the file
- Replacing LSP path
- Full processor stage reform (optional parallel)

---

## Remaining phases (after B)

### Phase A — Processor coexisting stages (still recommended, not blocking B)

[ProcessorPipelineArchitecture](Task%20-%20ProcessorPipelineArchitecture.md): durable siblings for structure / deps / architecture / analysis.

Dual path **already works** without full reform; reform helps if the forest must survive re-analysis cleanly.

### Phase C — Product polish

- Optional: remember last `structureSource` for **Open Again**.
- Richer kind→icon maps for humanized TS labels.
- Better scope rules / fewer false edges; language-specific tweaks in profiles if needed.
- More languages = more `LanguageProfile`s + grammars.

### Phase D — Default flip & sunset

- Default TreeSitter when dep quality acceptable.
- LSP optional or removed; retire `LSPServiceHint` etc. when ready.

---

## Do **not**

- Big-bang delete LSP before deps quality is acceptable.
- Force TS through dump `LSPCodeSymbol` / change `.codebase` schema for structure.
- Store full CST in `.codebase` by default.
- Build AI resolvers before a simple name linker.
- Premature “all languages” packaging.
- Reintroduce document APIs for TreeSitter.
- Put structure-backend forks in menus/UI beyond choosing `StructureSource`.
- Invent a second treemap / graph model for TS edges.

---

## Ordering vs other tasks

| Task | Relation |
|------|----------|
| Drop DocumentGroup + durable `codeFolder` | **Done** |
| Decouple Architecture from LSP types | **Done** (enabler) |
| TreeSitter Architecture Iteration 1 | **Done** (structure-only dual path) |
| **Deps linker on TS IR (Phase B)** | **Next** |
| Processor coexisting stages (full) | **Open** — optional chassis |
| Flattened treemap | Orthogonal UI |
| `.codebase` → project file | **Later** |

```text
[Done]  WindowGroup + import/export + codeFolder cache
[Done]  Architecture LSP-agnostic (kind String, CodeRange)
[Done]  TreeSitter Codebase + run(structureSource:) structure-only path
[Done]  Create-from-TreeSitter already reads symbol.references → edges
[Done]  Name/scope linker v0 + full TS artifact tree + fixture tests
        │
        ▼
[Later] Better resolution / processor reform / default flip / LSP sunset
```

---

## Immediate next actions

1. **Implement v0 linker** as scope-stack name resolution (register locals per scope → process refs/nested decls; lookup inward→outward). Output: forest copy with used-by on matched declarations.
2. **Wire** linker into TS retrieve → Architecture path (one call site before `generateArchitecture`).
3. **Filter** Architecture Create to declaration children only (if not already correct in UI).
4. **Tests**: same-file mutual recursion (order-independent locals); nested shadowing (inner wins); cross-file unique top-level; one edge through Architecture.
5. Manual smoke: **Open Swift Package Folder (new)…** — hierarchy **with** dependency arrows on a tiny sample.

---

## Success checklist

### Iteration 1 (structure only) — done

- [x] TreeSitter module produces multi-file forest (Swift + Python profiles)
- [x] Architecture from Tree-sitter without mutating LSP dump types
- [x] Shared `run(structureSource:)` with fork only at retrieve + Architecture create
- [x] Menus open TS path; metrics/UI consume same artifacts
- [x] Export still from durable `codeFolder` (text tree)
- [x] Unit tests for generator + Architecture conversion
- [x] `TreeSitterCodeSymbol.references` + Create-from-TS edge wiring ready (empty fuel)

### Iteration 2 (deps v0) — done

- [x] Scope-stack linker: per-scope register decls, then resolve refs (lookup top→root)
- [x] Output forest: declaration nodes carry used-by `ReferenceLocation`s
- [x] TS Architecture path shows useful edges (not only hierarchy)
- [x] Artifact tree keeps full Tree-sitter IR (decls + refs; refs also fuel used-by)
- [x] Fixture tests: mutual locals, shadowing, cross-file unique name; one Architecture edge
- [x] Clear path for quality: lexical v0 → imports/types/overloads/AI later

### Integration (full)

- [ ] Processor retains source + structure + analysis without enum erase (full reform)
- [ ] Optional default flip when ready
