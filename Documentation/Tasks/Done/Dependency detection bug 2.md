### Fixed

**Test:** `testExternalUseOfExtensionMember`

**Intention**

| Role | In fixture |
|------|------------|
| A | type being extended — **absent** from the forest |
| B | `extension A { func foo() {} }` |
| C | external `func c() { foo() }` (outside A and B) |

C uses a function declared in B → used-by on that function → dependency onto B.  
That alone must **not** create a reference to A (A may not even be analyzed).

**Fixture (hardcoded, stable):**
```swift
extension A {
    func foo() {}
}
func c() {
    foo()
}
```

### Cause (was)

Root index only registered **file-level** decls. Members nested under type-like
containers (including extensions) lived only in that body’s nested scope, so an
external caller never saw them.

### Fix

Phase 1 deep-registers name-binding decls into the root index for:

- file-scope declarations
- members of type-like containers (`class_declaration`, `protocol_declaration`,
  `class_definition`) — **including extension bodies**

Function/method locals stay body-scoped only (not published to root), so nested
shadowing still works. Extension containers still do not bind the extended type
name (bug 1).
