### Done

Generalized same-file preference to the whole forest hierarchy: a reference
prefers a declaration under the **most local enclosing folder** that uniquely
binds the name, before falling through to an outer (possibly ambiguous) scope.

**Test:** `testSameFolderCrossFileUseDespiteDuplicateElsewhere`

```text
Demo/
  A/
    Foo.swift   ← func foo() {}
    Bar.swift   ← func bar() { foo() }   // used-by on A/Foo.swift’s foo
  B/
    OtherFoo.swift ← func foo() {}       // must not erase A’s same-folder link
```

### Design (one mechanism)

Mirror the forest in the scope stack — every container that can introduce locality
pushes a scope filled with the decls that container owns:

```text
codebase / folder*   ← Scope(firstWinsOrAmbiguous): all name-binding decls in subtree
  └─ file            ← Scope(lastWins): that file’s top-level name-binding decls
       └─ decl body* ← Scope(lastWins): child decls
```

Lookup is a single inward→outward walk. The outermost folder **is** the root
index (`enterFolder` / `enterFile`); no separate phase-1 global fill.

### Acceptance

- [x] `testSameFolderCrossFileUseDespiteDuplicateElsewhere` passes
- [x] Existing linker tests still pass
- [x] No “search siblings when ambiguous” branch; no second lookup path
