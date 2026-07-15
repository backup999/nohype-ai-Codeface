### Fixed

**Test:** `testDuplicateRootNameStillLinksSameFileUse`

**Fixture:**
```text
A.swift  ← func foo() {}
B.swift  ← func foo() {}
           func bar() { foo() }
```

**Result (was):** fails at linker  
- used-by on B’s `foo` = **0**  
- only because A also declares `foo` (root name marked ambiguous)

### Expected

Same-file use in B should still link to B’s `foo` (or otherwise not drop the use
entirely). A second same-named decl elsewhere must not erase a real reference.

### Cause (was)

Root scope policy `rootFirstWinsOrAmbiguous`: second distinct binding of a name
unregisters it and marks the name unresolvable. Lookup then misses even when a
perfectly good same-file target exists. There was no file-level scope between
root and nested bodies.

### Fix

Phase 2 pushes a **file scope** (last-wins) registering that file’s top-level
name-binding decls before resolving its refs/bodies. Lookup still walks
inward→outward, so same-file top-level beats an ambiguous root entry. Cross-file
ambiguous names with **no** same-file target remain unbound.

### Note

Former test `testAmbiguousRootNamesDoNotBind` **encoded the old policy as desired
behavior**. Replaced by the expectation above.
