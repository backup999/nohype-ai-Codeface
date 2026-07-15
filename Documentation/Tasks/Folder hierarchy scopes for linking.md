### Goal

Generalize same-file preference to the whole forest hierarchy: a reference should
prefer a declaration under the **most local enclosing folder** that uniquely binds
the name, before falling through to an outer (possibly ambiguous) scope.

**Failing test:** `testSameFolderCrossFileUseDespiteDuplicateElsewhere`

```text
Demo/
  A/
    Foo.swift   ← func foo() {}
    Bar.swift   ← func bar() { foo() }   // expect used-by on A/Foo.swift’s foo
  B/
    OtherFoo.swift ← func foo() {}       // must not erase A’s same-folder link
```

Today: only **root + file + body** scopes exist. Root marks `foo` ambiguous → no
used-by. File scope on `Bar.swift` has no `foo`. Same-folder locality is invisible.

### Design principle (one mechanism, not a patch)

Do **not** add a one-off “if root is ambiguous, search sibling files in this folder.”
Mirror the forest in the scope stack: **every container that can introduce locality
pushes a scope** filled with the decls that container owns.

```text
codebase / folder*   ← Scope(firstWinsOrAmbiguous): all name-binding decls in subtree
  └─ file            ← Scope(lastWins): that file’s top-level name-binding decls
       └─ decl body* ← Scope(lastWins): child decls (unchanged)
```

Lookup stays **one** inward→outward walk. Locality is entirely “what is on the
stack,” not special-case search.

Root is not a separate policy island — it is the outermost folder scope (the
input `TreeSitterFolder`). File and body scopes stay last-wins; folder/root use
first-wins-or-ambiguous so **true** duplicates at that level stay unbound while
**unique within this subtree** still resolve.

### Why subtree registration per folder

Folder scope for `A` must include decls from `A/**` (all nested files), not only
`A`’s direct files. Otherwise sibling subfolders under `A` would not prefer each
other over an outer collision:

```text
A/Sibling/foo.swift   +   A/Nested/bar.swift { foo() }   +   B/foo.swift
```

With subtree fill: stack `[Demo, A, Nested, file, …]` → `A` uniquely binds `foo`
→ hit. With “direct files only,” `A` is empty and the name dies at ambiguous root.

Each decl is registered in **every ancestor folder scope** (and still only once
per file/body as today). Redundant, correct, O(depth) stack — same as nested
bodies already are.

What goes into a folder scope matches **today’s root registration** (file-level
name-binding decls + members of type-like containers, extensions do not bind the
type name). Reuse the same `registerDeclarations(…, publishIntoRoot:)` rules;
rename the flag if helpful (`publishIntoContainer` / shared predicate). File
scopes stay **top-level only** (bodies cover same-type members).

### Phase-2 shape (replace flat root + ad-hoc file push)

Unify walk so folder entry = push + register subtree + recurse + files + pop:

```text
link(folder):
  var stack = []
  var usedBy = [:]
  enterFolder(folder, pathPrefix: "", stack, usedBy)
  return rebuild(...)

enterFolder(folder, pathPrefix):
  push Scope(firstWinsOrAmbiguous)
  registerDeclarations(in: folder, pathPrefix, into: top)   // full subtree
  for sub in folder.subfolders:
    enterFolder(sub, join(pathPrefix, sub.name), ...)
  for file in folder.files:
    enterFile(file, join(pathPrefix, file.name), ...)
  pop

enterFile(file, filePath):
  push Scope(lastWins)
  register top-level name-binding decls of file only
  process(file.symbols, ...)   // existing ref + enterDeclBody
  pop
```

Phase-1 “fill one global root then walk with stack = [root]” collapses into this:
the outermost `enterFolder` **is** the root index. No second, divergent registration
path for “global only.”

Optional: keep a thin `link` that only allocates `usedBy` / calls `enterFolder` —
no parallel `registerDeclarations` + `resolveFiles` that disagree about scopes.

### Policy matrix (unchanged semantics, more levels)

| Scope            | Policy                    | Contents                                      |
|------------------|---------------------------|-----------------------------------------------|
| Folder (any depth) | firstWinsOrAmbiguous    | Subtree name-binding decls (same as old root) |
| File             | lastWins                  | That file’s top-level name-binding decls      |
| Decl body        | lastWins                  | Immediate child decls                         |

Ambiguous **at the innermost folder that still sees two bindings** → no bind from
that scope; outer scopes may still miss; file scope may still hit same-file.
That is the same rule as today’s root, applied at every folder depth.

### Acceptance

- [ ] `testSameFolderCrossFileUseDespiteDuplicateElsewhere` passes  
      (used-by on `A/Foo.swift`’s `foo` from `A/Bar.swift`)
- [ ] Existing linker tests still pass (same-file duplicate, extension member,
      extension vs type, nested shadowing, cross-file unique, architecture edge)
- [ ] Nested-folder case (optional follow-up test): unique under parent folder
      beats outer collision even when use is in a child subfolder and target is in
      a sibling subfolder — guaranteed by subtree registration, not extra code
- [ ] No “search siblings when ambiguous” branch; no second lookup path

### Non-goals

- Real module / access-control / import graphs  
- Preferring “closer path” by string distance without shared ancestor scope  
- Changing architecture edge construction; only used-by quality improves  

### Origin

Bug 3 fixed same-file erasure via a file scope. This task is the same idea one
level up (and every level up): **locality of the forest = locality on the stack.**
