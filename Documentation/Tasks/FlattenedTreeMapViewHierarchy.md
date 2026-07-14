# TreeMap: model frames + flattened view hierarchy (Option A)

## Context

The architecture treemap grew out of early‑2022 recursive SwiftUI: nested `GeometryReader`s, layout during body evaluation, and a sandwich of `ArtifactView` ↔ `ArtifactContentView`. Layout was later moved onto the view model (absolute frames) — the right idea — but the **view graph stayed recursively nested** and kept vestigial geometry measurement at each content level.

Symptoms of that stacking:

- Two types / coordinate spaces per level (box vs content surface)
- Inner `GeometryReader`s that no longer drive layout
- Fragile reparenting when selection or structure changes
- Hard to do continuous spatial transitions (e.g. zoom into a child while its container fades)

This document captures the preferred modernization: **Option A with a flat SwiftUI layer**.

## Product use cases (why flat matters)

These are **product-relevant** capabilities the recursive view hierarchy does not express well. The flat scene is not only a cleanup — it is the medium those features need.

### 1. Spatial zoom / drill-in

When the user focuses a nested artifact, the visualization should feel continuous:

- The target keeps a **stable identity** (same id in the flat list).
- Its frame **expands** toward the scope.
- Ancestor containers **fade / recede** instead of the tree being torn down and rebuilt as a new recursive root.

Recursive UI typically **reparents** content (old root content disposed, new subtree mounted), which breaks continuous zoom. One `ZStack` + model frames animates as a scene graph.

### 2. Cross-boundary dependency inspection

Inspecting dependencies should not be limited to **siblings under one parent**. Arrows may need to connect artifacts that:

- sit **one (or more) layer(s) deeper**, and  
- live under **different container parents**.

That requires:

- Endpoints in **one shared coordinate space** (scope-absolute frames), not local per-content `ZStack`s.
- An edge draw layer that can sit in a deliberate **depth band**, e.g.:

  ```text
  … ancestor / container boxes …
    cross-container edge (in front of A and B’s shells)
      … children of A and B …
  ```

  i.e. the arrow is **above** containers A and B but **behind** their children.

Recursive nesting only stacks “inside one content surface.” It cannot cleanly express that z policy for edges that cross container boundaries without lifting geometry **and** paint order to a global list — which is what the flat approach is from the start.

Together, zoom and dependency inspection show that Codeface implies a **flexible visualization canvas** (nodes + edges + explicit z), not a containment tree of SwiftUI views.

## Decision

| Layer | Strategy |
|-------|----------|
| **Layout** | Recursive in **data** on the view model (unchanged in spirit) |
| **Rendering** | **Flat** SwiftUI: one scope surface, sibling views positioned from frames |
| **Size input** | At most **one** root size observation (not per level) |
| **Not chosen** | Custom `Layout` as primary packing (Option B); full `Canvas` as the interactive UI (Option C) |

**Canvas** stays a possible future renderer for density; it is not the default because Codeface needs a real interactive UI (hover, path bar, selection, accessibility-friendly controls), not a pure plot.

## Target shape

```text
TreeMapScope (or equivalent)
  • observe root size once → updateLayout(selected, size)
  • empty / “doesn’t fit” / loading UI when appropriate
  • otherwise:

    ZStack (single coordinate space = scope content rect)
      1. edges (DependencyView or equivalent), ordered as desired
      2. artifact boxes: ForEach(visibleNodes) { box }
           • identity = artifact id
           • position/size = frame in **scope coordinates**
           • paint order = depth (parents under children) or explicit zIndex
```

There is **no** recursive `ArtifactBox → content → ArtifactBox` view tree for packing. Optional small subviews (header, icon) live **inside** each sibling box; they do not re-open a nested treemap coordinate system.

### Conceptual replacements for today’s files

| Today (approx.) | Role later |
|-----------------|------------|
| `TreeMap` + `RootArtifactContentView` | One scope entry: size, layout kick, empty states |
| `ArtifactContentView` | Dissolves into root `ZStack` layers (edges + boxes) |
| Recursive `ArtifactView` | Flat “box” views in `ForEach`, or one reusable box type **without nesting further maps** |
| `ArtifactHeaderView` / `DependencyView` | Keep as leaf helpers |

## Layout & coordinates

### Keep on the model

- Treemap split algorithm (LOC / components / gaps / minimum sizes)
- Per-node rectangles and derived UI geometry (header, collapse, font size, …)
- Dependency endpoint calculation from sibling frames
- Search filter and `showsParts` / “doesn’t fit” semantics

### Scope-absolute frames (required for flat views)

Recursive UI places children in **parent content** space (`contentFrame` local).  
A flat `ZStack` needs **one space** (the selected scope’s content rect).

When building `visibleNodes` (or when laying out), either:

1. **Write scope-absolute frames** into the render list, or  
2. **Transform** local frames through ancestor content origins once when flattening.

Edges must use the same space as boxes.

### Root size only

- Measure or observe the scope size **once** at the root (`onGeometryChange` or a single `GeometryReader` used only as a size source).
- Do **not** re-measure at each artifact depth.
- Feed `updateLayout(forScopeSize:applySearchFilter:)` (or successor) from that size and from selection / filter changes.

## Visibility & draw order

### Visible set

Walk the selected artifact’s tree (depth-first or precomputed list):

- Include a node if it should appear under the current filter / fit rules.
- Stop descending when parts are not shown (`showsParts != true`) if that remains the policy — or still include zero-size/opacity nodes if needed for transitions (see below).

### Paint order

In one `ZStack`, **list order (or `zIndex`) is painter order**. Treat it as a **scene depth policy**, not parent–child view nesting.

- Emit containers before descendants (e.g. sort by tree depth ascending), so inner artifacts draw on top of their containing boxes.
- For **sibling-only** edges, a simple “all edges under all boxes” band may suffice.
- For **cross-boundary dependency inspection**, edges often need a **mid depth band**: in front of the connected containers’ shells, behind their children (see [Product use cases](#product-use-cases-why-flat-matters)). That implies ordering (or per-edge `zIndex`) by something richer than a single global “arrows then boxes” split — e.g. interleave by tree depth.

Recursive views got crude stacking “for free” via nesting; they cannot express cross-container edge bands. Flat rendering makes order **explicit** and product-capable.

## Interaction

- Hover / focus / path bar: per-box handlers remain viable; use stable artifact ids.
- “Innermost under cursor” may need depth-aware hit testing if overlapping hits become ambiguous; nested views solved much of this implicitly.
- Selection / zoom drill-in should prefer **animating frames and opacity** over destroying identity by swapping an entirely new recursive content root when avoidable (see zoom use case above).

## Transitions & identity

A unified layer + stable identities enable continuous spatial motion (esp. **zoom / drill-in** and filter morphs):

- **Zoom into a nested artifact:** child’s frame expands toward the scope; ancestors fade/recede; same `ForEach` id so SwiftUI can interpolate (product use case §1).
- **Search filter:** keep nodes mounted when possible; animate frame → collapsed and opacity rather than unmounting large subtrees.
- **Scope change:** cross-fade or morph using the flat list instead of tearing down nested `GeometryReader` stacks.
- **Dependency inspection edges** can appear/move in scope space without living inside a single parent’s content stack (product use case §2).

Policy preference:

- Prefer **opacity / frame** over structural insert/remove of whole subtrees.
- Dual compile-time modes like `useCorrectAnimations` (fast prune vs always-layout-hidden) should collapse into **one** intentional strategy when this is implemented.

## Comparison (short)

| Approach | Packing | Views | GeometryReader | Arrows | Best for |
|----------|---------|-------|----------------|--------|----------|
| **A flat (this doc)** | Model frames | Flat siblings | 0–1 at root | Natural (frames on VMs) | Interactive map + spatial transitions |
| A recursive UI | Model frames | Nested boxes | 0–1 at root (ideally) | Natural | Smaller code move from status quo |
| B custom `Layout` | System `Layout` | Often recursive | 0 | Needs **frame export** (prefs/cache) | Pure box packing without stored frames |
| C `Canvas` | Model frames | Draw calls | 0–1 at root | Drawn with boxes | Density; weaker default for rich controls |

### “Frame export” (Option B only)

If packing happens inside `placeSubviews`, sibling rects are not automatically on view models for free-form edges. Dependency arrows would need an extra channel (preference keys, layout cache, or parallel model layout). Option A already stores frames where arrows need them.

## Non-goals (for this task)

- Rewriting the treemap **split heuristic** or metrics
- Moving layout off the main actor (optional later)
- Pure performance optimizations
- Replacing the whole app shell / navigation
- Making `Canvas` the primary interactive surface

## Migration sketch

1. **Document / assert** current data flow: selection → root size → `updateLayout` → frames → views.
2. **Remove inner `GeometryReader`** from content surfaces; size the parts stack from known frames. Prove no visual regression.
3. **Build a scope-absolute (or transformed) flat list** of drawable nodes + edges for the selected artifact (debug overlay first if useful).
4. **Render PoC:** one `ZStack` + `ForEach` boxes + edges; recursive view path behind a flag or deleted when PoC wins.
5. **Unify empty / fit / loading** at the scope entry; drop redundant wrappers (`TreeMap` vs root content) if thin.
6. **Animation policy:** one path for filter/resize/selection; retire dual animation modes when touching this code.
7. Later: Observation cleanup, fewer per-node update storms, optional Canvas only if measured need.

## Status quo map (reference)

Approximate current chain:

```text
TreeMap
 └─ RootArtifactContentView     // GeometryReader + layout + empty/spinner
      └─ ArtifactContentView    // GeometryReader + deps + ForEach ArtifactView
           └─ ArtifactView      // chrome + header + nested ArtifactContentView
                └─ …
```

Target:

```text
TreeMapScope
 └─ layout from root size
 └─ ZStack
      edges…
      ForEach(visibleNodesInScope) { ArtifactBox … }  // siblings only
```

## Success criteria

- [ ] No recursive artifact-map view nesting for packing
- [ ] At most one size observation for the map
- [ ] Boxes and arrows share one coordinate space
- [ ] Draw order keeps descendants above ancestors
- [ ] Artifact identity stable enough for continuous **zoom / drill-in** and filter transitions (product use case §1)
- [ ] Architecture allows **cross-container dependency arrows** with correct scope coordinates and depth-band z-order (product use case §2) — even if a first PoC only draws sibling edges
- [ ] Inner `GeometryReader` hierarchy gone from the treemap
