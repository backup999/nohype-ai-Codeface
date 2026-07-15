### Reproduced

**Test:** `testDuplicateRootNameStillLinksSameFileUse`

**Fixture:**
```text
A.swift  ← func foo() {}
B.swift  ← func foo() {}
           func bar() { foo() }
```

**Result: fails at linker**  
- used-by on B’s `foo` = **0**  
- only because A also declares `foo` (root name marked ambiguous)

### Expected

Same-file use in B should still link to B’s `foo` (or otherwise not drop the use
entirely). A second same-named decl elsewhere must not erase a real reference.

### Cause

Root scope policy `rootFirstWinsOrAmbiguous`: second distinct binding of a name
unregisters it and marks the name unresolvable. Lookup then misses even when a
perfectly good same-file target exists.

### Note

Former test `testAmbiguousRootNamesDoNotBind` **encoded this policy as desired
behavior**. Replaced by the failing expectation above.
