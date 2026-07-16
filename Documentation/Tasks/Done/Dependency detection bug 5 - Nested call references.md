### Done

Nested constructor / function calls inside outer calls (trailing closures,
argument lists) are projected as nested `call_expression` / `call` references
and participate in used-by linking.

**Test:** `testNestedCallInsideTrailingClosureLinksCrossFile`  
**Tree test:** `testSwiftNestedCallInsideTrailingClosure`

```text
AnalysisView/
  RootView.swift   ← Container { ChildView() }  // used-by on ChildView
  Child/
    ChildView.swift ← struct ChildView {}
```

### Design (Option A — open refs by default; leaf is the special case)

`LanguageProfile.Rule.opensChildren` defaults to **true**. Nested uses under
calls (and similar containers) stay in the tree. Only stacked same-name shells
opt out:

| Kind | Role | Opens children? | Rationale |
|------|------|-----------------|-----------|
| `call_expression` / `call` (default) | reference | **yes** | Args + trailing closures hold further uses |
| `inheritance_specifier` | reference | **no** | Nested `user_type` would re-emit the same type |
| Python `import_*` | reference | **no** | Loose name field would re-emit the same import |

**Code-tree shape:**

```text
property_declaration "body"
  ├── user_type "View"
  └── call_expression "Container"
        └── call_expression "ChildView"    // nested under outer call
```

**Linker:** when processing a `.reference`, resolve used-by, then
`process(nodes: node.children, …)` so nested call refs link too (no new scope).

### Real-world

`CodebaseAnalysisView.body` composes sibling views inside
`NavigationSplitView` / `.inspector` trailing closures → folder deps onto
Navigator / Central / Inspector.
