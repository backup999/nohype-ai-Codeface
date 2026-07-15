### Reproduced

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

**Result: fails at linker**  
- used-by count on extension member `foo` = **0**

### Expected

- `foo` (in B) has used-by from the call in `c`
- Architecture can lift that to a dep onto B when the use site is outside B
- No requirement that primary type A exist; no used-by invented on A

### Cause

v0 registers only **top-level** decls into the root scope. Members nested under
an extension stay in that extension’s body scope, so an external caller never
sees them. This is independent of bug 1 (type-name clash with extensions).

### Not the same as bug 1

Bug 1: type **name** dropped because extension also registered as that name.  
Bug 2: extension **members** are invisible to symbols outside the extension body.
