### Reproduced

**Test:** `testSameFileTypeMentionDespiteRootExtensionElsewhere`

**Fixture (hardcoded, stable):**
```text
T.swift          ← struct T { var x: T }
T+Ext.swift      ← extension T {}
```

**Result: fails at linker**  
- used-by count on struct `T` = **0**

### Cause

Tree-sitter treats `extension T` as another root `class_declaration` named `T`.  
v0 root policy: **duplicate root name → never bind**.  
With only `T.swift`, a single root `T` binds and the property type mention gets used-by. Adding the extension drops the name entirely.

### Origin

Observed on real App sources: `CodePosition` in `Basic Types/CodeRange.swift` + `extension CodePosition` in `CodeRange+LSPRange.swift`. Architecture edges disappear when opening full App vs Basic Types alone.
