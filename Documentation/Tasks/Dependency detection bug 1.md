### Reproduced

**Test:** `testCodeRangeDepsWhenNestedUnderAppWithExtensionElsewhere`

**Fixture (minimal App):**
```text
App/
  Basic Types/CodeRange.swift          ← struct CodePosition
  Codebase Architecture/.../CodeRange+LSPRange.swift  ← extension CodePosition
```

**Result: fails at Stage 1 (linker)**  
- used-by count on struct `CodePosition` = **0**  
- Architecture edge count = **0** (follows from empty used-by)

### Cause

Tree-sitter treats `extension CodePosition` as another root `class_declaration` named `CodePosition`.  
v0 root policy: **duplicate root name → never bind**.  
Basic Types alone has one `CodePosition` → works. Full App adds the extension → name is dropped.
