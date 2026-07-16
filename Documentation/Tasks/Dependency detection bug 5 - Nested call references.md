# Dependency detection bug 5 — Nested call references (SwiftUI composition)

## Status

**Open.** Regression test exists and fails; fix not started.

| Piece | Status |
|-------|--------|
| Minimal failing test | **Done** — `testNestedCallInsideTrailingClosureLinksCrossFile` |
| Code-tree projection of nested callees | **Open** |
| Linker walks nested ref children (if nested under refs) | **Open** (depends on projection shape) |
| Docs (`TreeSitter - How It Works.md` leaf-ref rule) | **Open** |

## Origin

Applying Codeface to its own sources: `CodebaseAnalysisView.swift` clearly depends on the three sibling folders under `Codebase Analysis View/` (`Navigator View`, `Central View`, `Inspector View`), but those folder edges are missing.

Call sites look like ordinary type initializers, yet they sit **inside** other call expressions’ trailing closures / argument lists:

```swift
NavigationSplitView(columnVisibility: $columnVisibility) {
    CodebaseNavigatorView(...)   // nested in trailing closure
}
detail: {
    CodebaseCentralView(...)      // nested in labeled trailing closure
}
.inspector(isPresented: ...) {
    CodebaseInspectorView(...)    // nested in member-call trailing closure
}
```

## Symptom (measured)

Fixture (hardcoded, stable):

```text
AnalysisView/
  RootView.swift   ← struct RootView {
  │                    var body: some View {
  │                      Container { ChildView() }
  │                    }
  │                  }
  Child/
    ChildView.swift ← struct ChildView {}
```

**Test:** `TreeSitterReferenceLinkerTests.testNestedCallInsideTrailingClosureLinksCrossFile`

| Expectation | Actual (pre-fix) |
|-------------|-------------------|
| RootView tree contains ref name `ChildView` | refs = `["View", "Container"]` only |
| `ChildView` used-by includes `RootView.swift` | `references == []` |

So the linker never sees the nested use: the gap is **upstream of linking**, in code-tree projection.

## Root cause

### 1. Generator treats every reference as a leaf

`CodeTreeGenerator.collect` (shared walk):

```text
if node type ∈ profile.rules and name readable:
    emit CodeNode
    if role == .reference:
        children = []          ← stop CST walk here
    else:
        children = full CST children (filtered)
```

**Why that rule existed:** type mentions often stack several CST shells for one token (`inheritance_specifier` → `user_type` → `Bar`). Opening every reference would double-count the same name.

**What it breaks:** `call_expression` (and Python `call`) legitimately **contain** other refs in arguments and trailing closures. Stopping at the outer call drops all nested callees.

```text
Container { ChildView() }
     │
     ▼  projected today
  call_expression "Container"   (leaf — ChildView never visited)
```

### 2. Linker only resolves top-level refs under decls

`TreeSitterReferenceLinker.process`:

- `.reference` → name lookup, **no recursion into `node.children`**
- `.declaration` → push body scope, process children

Even after nested calls are projected, if they live **as children of a call ref**, the linker must walk those children. If projection **flattens** nested refs as siblings under the enclosing declaration, the linker needs no change.

## Goals

1. Nested constructor / function calls inside outer calls (trailing closures, argument lists) produce `call_expression` (or Python `call`) reference nodes.
2. Those refs participate in used-by linking exactly like today’s top-level body calls.
3. Real-world: `CodebaseAnalysisView` → sibling view types → folder edges onto Navigator / Central / Inspector when analyzing the app itself.
4. **Do not** reintroduce double-counting for stacked type shells (`inheritance_specifier` / `user_type`, Python base identifiers, etc.).

## Non-goals

- Overload resolution, import graphs, or SwiftUI-specific semantics.
- Changing folder-scope / same-file / extension policies (bugs 1–4).
- Architecture / treemap layout beyond edges that fall out of used-by.
- Full CST retention for all reference kinds.

## Design options

### A — Profile-driven “open reference” kinds (recommended)

Keep the default **leaf reference** rule. Opt **specific** node types into opening their CST children:

| Kind (examples) | Role | Opens children? | Rationale |
|-----------------|------|-----------------|-----------|
| `call_expression` (Swift) | reference | **yes** | Args + trailing closures hold further uses |
| `call` (Python) | reference | **yes** | Same |
| `inheritance_specifier`, `user_type`, `import_*`, bare `identifier` | reference | **no** | Stacked shells / one surface name |

**Code-tree shape after fix:**

```text
property_declaration "body"
  ├── user_type "View"
  └── call_expression "Container"
        └── call_expression "ChildView"    // nested under outer call
```

**Linker change (required for nested-under-ref shape):** when processing a `.reference`, still resolve it, then `process(nodes: node.children, …)` so nested call refs link too. Declarations unchanged.

**Profile API sketch** (minimal):

```swift
struct Rule {
    var role: TreeSitterCodeSymbol.Role
    var name: NameSource
    /// When true, walk CST children even if `role == .reference`.
    /// Default false — preserves leaf behavior for type shells.
    var opensChildren: Bool = false
}
```

Generator:

```text
let open = rule.role == .declaration || rule.opensChildren
children = open ? childrenForSelectedNode(...) : []
```

**Pros:** Local, explicit, matches “leaf by default, calls are containers of uses.”  
**Cons:** Nested ref trees; linker must recurse into ref children once.

### B — Flatten nested refs as siblings under the enclosing declaration

On reference hit: emit the leaf ref, **also** walk CST children, but append nested code nodes to the **parent’s** child list (return `[leaf] + nested` from `collect`) rather than nesting under the leaf.

```text
property_declaration "body"
  ├── user_type "View"
  ├── call_expression "Container"   // leaf
  └── call_expression "ChildView"   // sibling of Container, not child
```

**Pros:** Linker `process` unchanged (still only walks under declarations).  
**Cons:** Loses call nesting structure; easier to accidentally double-count if a walked child re-emits the same call shell; slightly surprising tree for metrics/UI if anything ever shows ref subtrees.

### Recommendation

**Option A.** Nesting under the outer call matches the CST and future tools (e.g. “refs inside this call”). One small, obvious linker recursion is cheaper than a flatten special case that reimplements parent insertion.

## Implementation plan

### Step 0 — Keep the red test (already done)

- `testNestedCallInsideTrailingClosureLinksCrossFile` stays red until Steps 1–2 land.
- Do not weaken it to “document the bug”; it is the acceptance gate.

### Step 1 — Projection: open children for call-like refs

**Files**

- `Code/App/TreeSitter Codebase/Language Support/LanguageProfile.swift`
- `Code/App/TreeSitter Codebase/Load/CodeTreeGenerator.swift`
- `Code/App/TreeSitter Codebase/Load/CodeTreeGeneratorTests.swift`

**Work**

1. Add `opensChildren: Bool = false` (or equivalent) on `LanguageProfile.Rule`.
2. Set `opensChildren: true` on Swift `call_expression` and Python `call`.
3. In `CodeTreeGenerator.collect`, open children when `rule.role == .declaration || rule.opensChildren`.
4. Update / extend `CodeTreeGeneratorTests`:
   - Existing `testSwift` / `testPython` still pass (no nested-call fixtures there).
   - **New** tree test, e.g. `testSwiftNestedCallInsideTrailingClosure`:

     ```swift
     func outer() {
         container { child() }
     }
     ```

     Expect `outer` → `call_expression "container"` → child `call_expression "child"` (and no loss of `container`).

5. Sanity: inheritance fixture still emits **one** ref for `Bar` in `struct Foo: Bar` (no `user_type` sibling under `inheritance_specifier`).

### Step 2 — Linker: process children of references

**Files**

- `Code/App/TreeSitter Codebase/Link/TreeSitterReferenceLinker.swift`
- Existing `TreeSitterReferenceLinkerTests.swift` (red test + suite)

**Work**

1. In `process`, for `.reference` after (or before) name lookup:

   ```text
   case .reference:
       resolve used-by for this node (existing shouldAttemptNameLookup / lookup)
       process(nodes: node.children, …)   // NEW — nested call args / closures
   ```

2. Do **not** push a new scope for reference children (calls do not introduce name bindings). Nested decls inside trailing closures (e.g. local `func` in a closure) are rare; if they appear as declaration children under a call, current policy can be revisited later — **out of scope** unless a test forces it. Prefer only emitting further **references** under opened call nodes if that simplifies invariants; walking full `childrenForSelectedNode` may also surface nested decls inside closures — acceptable if linker’s existing `enterDeclBody` path is only reached for `.declaration` nodes in `process` (already true when recursing with the same `process`).

3. Confirm red test turns green: `ChildView` in `rootRefs` **and** used-by path `RootView.swift`.

### Step 3 — Extra coverage (small, high value)

Add only what locks the real-world shapes:

| Test | Fixture intent |
|------|----------------|
| Already: nested trailing-closure cross-file | SwiftUI `Container { ChildView() }` |
| Optional: member call + trailing closure | `host.modifier { ChildView() }` → still projects `ChildView` |
| Optional: argument-list nesting | `container(ChildView())` (no trailing closure) |
| Optional: multi-sibling like AnalysisView | one file calling `A()`, `B()`, `C()` in separate trailing closures → three used-by targets |

Keep fixtures hardcoded and tiny (same style as bugs 1–4). Prefer linker-level used-by asserts; tree-level only where it documents projection.

### Step 4 — Documentation

Update `Documentation/TreeSitter - How It Works.md` § generator walk:

- Replace absolute “References are leaves” with:
  - **Default:** references are leaves (stacked type shells).
  - **Exception:** call-like kinds (`opensChildren`) nest further code nodes so args / trailing closures remain dependency fuel.
- Point at this task / the regression test name.

When fixed, move this file to `Documentation/Tasks/Done/` (or add a short “Fixed” header like bugs 1–4) and tick the checklist below.

### Step 5 — Manual smoke (app-on-itself)

1. Open the Codeface app source folder via the TreeSitter path.
2. Navigate to `Codebase Analysis View` (or the folder that contains `CodebaseAnalysisView.swift` + the three sidebars).
3. Expect dependency edges from the analysis view file/part onto **Navigator View**, **Central View**, and **Inspector View** (or the types/files therein).
4. Spot-check an unrelated type-inheritance edge still looks sane (no duplicate arrow spam).

## Risk notes

| Risk | Mitigation |
|------|------------|
| Double-counting type refs | Only open call-like kinds; keep inheritance / `user_type` closed |
| Noisy trees (many nested calls) | Acceptable — calls were always intended as dependency fuel; depth is real structure |
| Linker infinite recursion | Trees are finite CST projections; no cycles |
| Nested **declarations** inside closures under a call node | `process` already branches on role; decls get `enterDeclBody`. If noise appears, narrow opened walk later (e.g. only collect reference-typed children) |
| Python parity | Flip `opensChildren` on `call` in the same PR so languages stay symmetric |

## Acceptance checklist

- [ ] `testNestedCallInsideTrailingClosureLinksCrossFile` passes
- [ ] New / updated `CodeTreeGenerator` nested-call tree test passes
- [ ] Existing TreeSitter generator + linker + architecture tests still pass
- [ ] Inheritance / type-mention cases still single-count surface names
- [ ] App-on-itself: `CodebaseAnalysisView` shows deps onto the three sibling view folders
- [ ] `TreeSitter - How It Works.md` updated for non-leaf call refs
- [ ] This task marked Done / moved under `Tasks/Done/`

## Suggested PR shape

Single focused PR (or two stacked commits):

1. **Projection** — `opensChildren` + generator + tree test  
2. **Linker** — process ref children + green linker regression  

No architecture-layer changes expected if used-by is correct; folder edges are derived downstream.
