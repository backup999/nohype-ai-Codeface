### Fixed

**Test:** `testSameFileTypeMentionDespiteRootExtensionElsewhere`

**Fixture (hardcoded, stable):**
```text
T.swift          ← struct T { var x: T }
T+Ext.swift      ← extension T {}
```

### Cause

Tree-sitter models `extension T` as another root `class_declaration` named `T`
(`declaration_kind` = `extension`). v0 root policy treated that as a second binding of
`T` → **ambiguous, never bind** → same-file property type mentions lost used-by.

### Fix

`TreeSitterReferenceLinker` skips scope registration for decls whose
`declaration_kind` is `extension`. Extensions remain structural declarations
(containers for members) but do not introduce a type-name binding.

### Origin

Observed on real App sources: `CodePosition` in `Basic Types/CodeRange.swift` +
`extension CodePosition` in `CodeRange+LSPRange.swift`. Architecture edges
disappeared when opening full App vs Basic Types alone.
