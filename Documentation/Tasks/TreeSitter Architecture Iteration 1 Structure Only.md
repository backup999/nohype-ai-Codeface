# Task: TreeSitter → Architecture (iteration 1 — structure only)

## Goal

First end-to-end TreeSitter path that produces the **same `Code*Artifact` shape** as the LSP path, **without** dependency detection.

| In scope | Out of scope (later) |
|----------|----------------------|
| Evolve TS IR so it can convert to Architecture | Name-match / AI dep linking |
| Folder + file text → declaration hierarchy | Full processor coexisting-stages reform (desirable but not required for a vertical slice) |
| Map declarations → `CodeSymbolArtifact` / file / folder graphs | Used-by locations equivalent to `CodeSymbol.references` |
| Empty sibling graphs (or edges list empty) so Architecture metrics/UI still run | Perfect ranges/kind parity with LSP |
| Reuse Architecture **edge wiring algorithm later** unchanged | Replacing LSP as default |
| Readable free-string kinds (`SymbolKindDisplay`) | Changing `.codebase` dump schema |

Parent roadmap: [Integrate TreeSitter Analysis](Task%20-%20Integrate%20TreeSitter%20Analysis.md).  
Architecture seam (done): [Decouple Architecture from LSP Types](Task%20-%20Decouple%20Architecture%20from%20LSP%20Types.md).

## Why this iteration is small

LSP dump stores **used-by** locations per symbol; **Architecture “Create from Codebase”** turns them into per-scope graphs (sibling depends-on via range containment + bubble-up).

First TS iteration only needs:

```text
filesystem text  →  TS structure IR (decls nested)  →  Code*Artifact (hierarchy)
```

Dependencies: **none yet**. Artifact graphs exist but stay empty of edges (same as “codebase with no references”). Metrics / treemap still work (pure nesting + LOC).

When dep detection exists later, produce **`references`-shaped used-by lists** (or the same location type Architecture already consumes) and **reuse the existing Create-from-* wiring almost unchanged**.

## Decisions (locked for iter 1)

1. **Do not invent a parallel artifact model.** Target is existing `CodeFolderArtifact` / `CodeFileArtifact` / `CodeSymbolArtifact`.
2. **References for this path = empty.** No fake edges; no premature linker.
3. **Only declarations build the Architecture symbol tree.** `CodeNode.role == .reference` is kept in the IR for later linking, but **not** turned into symbol children in the treemap (unless a future product decision says otherwise).
4. **Kinds:** free `String` via existing `SymbolKindDisplay.kindName(nodeKind:refinedKind:)` (prefer `declaration_kind` when present).
5. **Ranges required on IR.** Architecture needs `CodeRange` for LOC, sort, eventual dep wiring. PoC `CodeNode` must gain range (and ideally selection-ish range — body vs name; v0 may set both equal if only one span exists).
6. **Adapters live outside pure Architecture.** Parallel the LSP convertors (`Create from Codebase/`): e.g. `Create Architecture from TreeSitter/` (or under TreeSitter module). Do **not** import TreeSitter into core Architecture types.
7. **Throw-away after convert is fine for this iter.** No durable CodeNode cache required yet; processor reform can add that later.

## Current gaps (PoC → Architecture)

| Gap | Action |
|-----|--------|
| `CodeNode` has no ranges | Capture `node.pointRange` / equivalent when building `CodeNode` |
| IR is per-file top-level list, not folder forest | Introduce multi-file envelope (paths + per-file root nodes / text) |
| References mixed into tree | Filter: only nest `.declaration` children when mapping to symbols |
| No convertor | New mapper → `Code*Artifact` constructors |
| Hard to run without LSP | Entry: folder path or existing text-bearing `CodeFolder` **before** symbol retrieve |

## Target data flow

```text
                    folder URL / CodeFolder (text+names only)
                                    │
                                    ▼
              per supported file: CodeTreeGenerator.generateTree
                                    │
                                    ▼
              ProgramForest  (folder tree of ProgramFile → [CodeNode])
                 CodeNode:
                   role, kind, name, attributes
                   range, selectionRange   ← NEW
                   children
                                    │
                    (optional: drop ref-only subtrees for architecture)
                                    │
                                    ▼
         Create Architecture from TreeSitter  (adapter)
                                    │
                                    ▼
                         CodeFolderArtifact
                         · empty edges everywhere
                         · kind strings humanized
                         · ranges from CodeNode
                                    │
                                    ▼
                    existing metrics + analysis UI
```

Suggested names (TBD at implement time): `ProgramForest` / `ProgramFile` or reuse thin Folder-like TS-only types. Keep them **TreeSitter-module–local**, not Architecture.

## Implementation phases

### Phase A — IR: ranges on `CodeNode`

1. Add to `CodeNode`:
   - `range: CodeRange` (or a PoC-local range type mapped at the adapter — prefer reusing Architecture’s `CodeRange` only if that package layering is clean; else local type + convert once)
   - `selectionRange: CodeRange` (v0 = name identifier span if easy, else `range`)
2. `CodeTreeGenerator.collect` fills ranges from SwiftTreeSitter `Node` (line/character 0-based — match Architecture conventions).
3. Fix unit tests expectations for equality / sample nodes.
4. **Still no deps.**

Stop: parse still works; nodes have spans.

### Phase B — Multi-file structure extraction

1. Walk a folder (or text-only `CodeFolder`): file endings → `SourceLanguage?` (skip unknown).
2. For each language file: read text → `generateTree` → store path-relative-to-root + nodes + lines/text.
3. Result type: e.g. `TreeSitterCodebase` / forest root (folder / file hierarchy mirroring filesystem managed files).
4. Unit tests: small fixture folders (Swift + Python) produce non-empty forest and ranges.

Stop: can build hierarchical structure IR without Language Server.

### Phase C — Convert declarations → Architecture (empty deps)

1. New adapter (sibling to LSP Create-from path), e.g.:

   - `CodeFolderArtifact.init(treeSitterForest:…)`
   - `CodeFileArtifact` from file + top-level **declaration** nodes
   - `CodeSymbolArtifact` from one declaration node + nested declaration children

2. Mapping rules:
   - `name` ← `CodeNode.name`
   - `kind` ← `SymbolKindDisplay.kindName(nodeKind:attributes[declaration_kind])`
   - `range` / `selectionRange` ← IR
   - `code` ← slice file lines by range (reuse `getCode(of:inFileLines:)` idea)
   - `subsymbolGraph` ← insert nested **declaration** children only; **no edges**
   - Skip / ignore `.reference` nodes in this conversion (leave them in forest for later)

3. Folder/file graph: insert parts; **no** `additionalReferences` wiring (empty arrays). Still call `filterEssentialEdges()` if desired (no-op on empty edges).
4. Do **not** call LSP `generateArchitecture` for this path.

Stop: pure hierarchy `CodeFolderArtifact` from TS.

### Phase D — Wire a runnable path (minimal)

Pick the thinnest switch that does not block iteration:

**Option D1 (recommended for iter 1):** Developer/debug toggle or temporary processor branch: “Analyze folder with TreeSitter (structure only)” — no LSP server, FS read → Phase B → Phase C → existing analysis step.

**Option D2:** Behind settings `structureBackend` (more polished, more UI work).

Non-goals for this phase: import `.codebase` dump still uses LSP symbols inside the file; don’t rewrite dump.

Stop: open a Swift (or Python) folder in app, see treemap of types/functions with LOC colors; no dependency arrows / empty graphs OK.

### Phase E — Guardrails & docs

1. Tests: declaration nesting Cf. fixture source; kind humanize; no edges.
2. Note in Integrate TreeSitter task: Iter 1 landed (structure-only).
3. Explicit hook for Iter 2: attach used-by locations shaped like `CodeSymbol.ReferenceLocation` (path + `CodeRange`) so existing Create wiring reuses.

## Iter 2 preview (not this task)

Feed Architecture the same “is used by” fuel the LSP dump provides:

```text
for each declaration unit:
  usedBy: [(filePathRelativeToRoot, range), ...]
```

Built by future name/scope linker on **references** in the CodeNode forest. Then:

- Prefer reusing the **bubble-up + sibling containment** pass already in Create-from Codebase (extract shared graph builder if needed so LSP dump and TS both call one place).
- Or produce edges in a deps stage and apply them onto artifact graphs directly — second choice only if shared builder costs more than it’s worth.

## Non-goals

- Dependency detection, edges, essential-edge filtering semantics well-studying  
- Full processor field reform (unless a few lines of path hook require it)  
- Saving `CodeNode` into `.codebase`  
- Universal language support (use PoC: Swift + Python)  
- Removing LSP path  
- Perfect selection ranges / overload accuracy  

## Definition of done

- [ ] `CodeNode` carries range (+ usable selection range policy documented)
- [ ] Folder/file extraction builds multi-file IR without LSP
- [ ] Conversion produces `CodeFolderArtifact` hierarchy with nested symbols for declarations only
- [ ] All graph edges empty; Architecture / metrics / UI path still succeeds
- [ ] Kind labels readable (humanize / `declaration_kind`); not raw snake_case in inspector
- [ ] At least one automated fixture test + one manual folder open path
- [ ] Architecture folder remains free of TreeSitter **and** of new SwiftLSP kinds (adapters only)
- [ ] No dependency algorithm outside reuse placeholder comments / empty `usedBy`

## Immediate next actions

1. Add ranges to `CodeNode` + generator + tests.  
2. Forest builder over folder text.  
3. Adapter: declarations → `Code*Artifact` with empty graphs.  
4. Temporary processor entry to exercise UI.  
5. Stop; schedule Iter 2 for used-by + shared Architecture wiring reuse.
