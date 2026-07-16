# Dependency detection bug 6 — Parameter bindings (implementation plan)

**Status:** plan only — reproduction tests exist; fix not implemented.

## Symptom (observed)

Opening Codeface on its own `App/` sources yields a false folder edge:

```text
@Code/App/Basic Types  →  @Code/App/Codebase Architecture
```

True direction is Architecture → Basic Types (`CodeRange` / `CodePosition` uses). The reverse edge is wrong.

### Reproduction tests (already land; broad symptom checks)

| Test | File | Expectation |
|------|------|-------------|
| `testSubscriptBaseDoesNotLinkToUnrelatedProperty` | `TreeSitterReferenceLinkerTests.swift` | No used-by on foreign `lines` property |
| `testSubscriptBaseDoesNotCreateFolderEdgeOntoUnrelatedProperty` | `Architecture Creation Tests.swift` | No folder edge BasicTypes → Architecture |

Fixture (minimal, stable):

```text
App/
  BasicTypes/Range.swift   ← func getCode(fromLines lines: [String]) { lines[0] }
  Architecture/File.swift  ← class File { let lines: [String] }
```

Both tests currently **fail** (documents the bug).

---

## Root cause

### Real-world site

```swift
// Basic Types/CodeRange.swift
func getCode(fromLines lines: [String]) -> String? {
    return lines[start.line ... end.line].joined(separator: "\n")
}

// Codebase Architecture/.../CodeFileArtifact.swift
let lines: [String]
```

### Mechanism

1. Tree-sitter models the **subscript** `lines[...]` as a `call_expression` whose surface name is `lines` (often nested under outer calls such as `joined` because call refs open children).
2. The linker does bare-name lookup for that reference.
3. The function **parameter** `lines` is **not** in the code tree as a declaration, so it never enters the function body scope.
4. Folder scopes **do** publish type members (`CodeFileArtifact.lines`), so lookup binds the local subscript to that foreign property.
5. Architecture edge wiring: used-by location in Basic Types + decl in Architecture → edge Basic Types → Architecture.

### Code-tree shape today (relevant fragment)

```text
function_declaration "getCode"
  ├── user_type "String"          // param type only (reference)
  ├── user_type "String"          // return type
  └── call_expression "joined"  call_host=lines
        └── call_expression "lines"   // subscript base — unbound locally
```

There is no declaration child named `lines` for the parameter.

### Why local binding would fix *this* edge

`enterDeclBody` already registers **child declarations** of a function into a body scope (`lastWins`) before resolving refs. Lookup is inward→outward. If `parameter "lines"` were a name-binding child of `getCode`, the subscript call would resolve there and would **not** fall through to Architecture’s property.

Linker change for the happy path is expected to be **zero or near-zero**: reuse existing body-scope registration. The gap is **projection** (code tree), not a new resolution policy.

---

## Grammar reality (Tree-sitter already has the data)

Swift tree-sitter exposes a proper CST node (not a bare loose identifier):

| Node | Role for us | Name field |
|------|-------------|------------|
| `parameter` | local binding in functions / inits | field `"name"` → `simple_identifier` (internal name) |
| optional `external_name` | call-site label only (`fromLines`) | **do not** use for scope binding |
| `lambda_parameter` | same idea in closures | field `"name"` when present |

Grammar sketch:

```text
parameter:
  [external_name: simple_identifier]
  name: simple_identifier
  ":"
  type: …
```

So for `fromLines lines: [String]`:

- external label: `fromLines` (API surface; not a body binding)
- **local binding name: `lines`** ← this is what scope resolution needs

**Conclusion:** Tree-sitter detects parameter names. We currently drop them in the profile filter (`LanguageProfile` has no rule for `parameter`). Root-cause fix is to **project** those nodes into `TreeSitterCodeSymbol` as declarations, not to invent names heuristically.

`TreeSitterCodeSymbol` itself needs no schema change for v1: `role = .declaration`, `kind = "parameter"`, `name = <local binding>` already fit the model. Extending the type (e.g. attributes like `declaration_kind = "parameter"`, or a dedicated role later) is optional polish, not required for linking.

---

## Proposed design

### Principle

**Use grammar-provided parameter nodes as body-local name bindings**, so exact-name lookup prefers them over distant same-named members — same stack walk as nested locals / file scopes (bugs 3–4).

### Layering

```text
CST (tree-sitter-swift)
  parameter { name: lines, external_name: fromLines, type: … }
        │
        ▼  LanguageProfile + CodeTreeGenerator   ← primary change
TreeSitterCodeSymbol
  declaration kind=parameter name=lines
        │
        ▼  TreeSitterReferenceLinker.enterDeclBody  ← already registers child decls
body scope: lines → DeclKey(getCode’s param)
        │
        ▼  lookup("lines") for subscript call
used-by on param (local) — not on File.lines
```

### 1. Projection (`LanguageProfile` / name helpers)

**Swift**

- Add rule:
  - `"parameter": Rule(role: .declaration, name: …)`
- Name source must yield the **internal** binding:
  - Prefer field `"name"` as `simple_identifier` text (not the whole `parameter` span, not `external_name`).
  - If a dedicated `NameSource` case is clearer than `.field("name")` (field `"name"` on `parameter` is overloaded in node-types with type-ish children in the JSON union), add e.g. `.swiftParameterName` that reads `child(byFieldName: "name")` only when it is / contains `simple_identifier`.
- Selection range: name identifier span (consistent with properties).
- Open children: **yes** (default) so parameter **types** still project as `user_type` references under the parameter (today those types appear as direct children of the function because the parameter node is skipped; after the change they should nest under `parameter` — update structural tree tests accordingly).

**Also project under inits / methods**

- Same `parameter` node under `init_declaration` and method `function_declaration` — one rule covers all parents; generator already walks children of selected decls.

**Closures (recommended same PR if cheap)**

- `"lambda_parameter": Rule(role: .declaration, name: …)` with the same internal-name rule.
- Shadowing for `{ lines in lines[0] }` is the same class of bug.

**Python (same PR or immediate follow-up)**

- Grammar has `parameters` / `default_parameter` / `typed_parameter` under `function_definition`.
- Mirror the idea: project name-binding parameter forms as declarations so Python does not reintroduce the same false-positive class.
- Out of scope only if name extraction is messy; then track as bug 6b.

### 2. Linker (`TreeSitterReferenceLinker`)

Expected behavior with **no policy change**:

| Mechanism | Effect on parameters |
|-----------|----------------------|
| `enterDeclBody` | Registers `parameter` children into body scope (`lastWins`) |
| `isTypeLikeContainer` | `function_declaration` is **not** type-like → parameters are **not** published into folder scopes |
| `introducesNameBinding` | Parameters are not extensions → they bind |

**Verify explicitly** (add/adjust unit expectations if needed):

- Parameter names must **not** appear in folder/root indexes (would create new false edges the other way: external `lines` use → random function’s parameter).
- Body-local use of parameter name resolves to the parameter’s `DeclKey` (file + range).

Optional hardening (only if a test proves need):

- Treat `kind == "parameter"` (and lambda) as always body-local even if a future parent were type-like — belt and suspenders.

### 3. Architecture layer

No special edge rule. Once used-by leaves Architecture’s `lines` property, the folder edge disappears.

**Side effect:** parameters become nodes in the symbol graph / UI hierarchy under their function (same as any other projected declaration). Acceptable: they are real bindings. If UI noise becomes an issue later, filter by kind at presentation time — **not** by dropping them from the analysis tree.

**Self-edge note:** `lines[0]` may attach used-by to the parameter itself (subscript modeled as call named `lines`). That is local and should not create cross-folder edges. Do not block the fix on “pretty” self-used-by; subscript modeling is a separate concern (see Non-goals).

### 4. What we are *not* doing in this bugfix

| Approach | Why not as primary fix |
|----------|------------------------|
| Stop treating subscripts as `call_expression` named like the base | Complementary hygiene; does not restore general local shadowing for other param uses |
| Unpublish all properties from folder scopes | Too blunt; breaks legitimate cross-file member links |
| Heuristic “don’t link lowercase free calls to properties” | Fragile; ignores that Tree-sitter already names parameters |

---

## Implementation steps

1. **Confirm CST** (one-off / test dump)  
   Parse `func getCode(fromLines lines: [String]) { lines[0] }` and assert a `parameter` node with name field `lines` exists under the function. Documents that the fix is profile-side, not grammar-side.

2. **Profile: project `parameter` as declaration**  
   - `LanguageProfile.swift` (Swift rules + name/selection helpers).  
   - Optional: `lambda_parameter` in the same change set.

3. **Tree tests** (`CodeTreeGeneratorTests`)  
   - Structural: `getCode` children include `declaration parameter "lines"` with nested type ref(s).  
   - External label must not become the symbol name (`fromLines lines:` → name `lines`).

4. **Linker tests**  
   - Keep symptom tests; they should flip to **pass**.  
   - Optional positive: used-by on the parameter from the subscript (local), and still empty used-by on foreign `File.lines`.  
   - Optional: parameter name does not steal cross-file uses when no local binding exists (folder publish check).

5. **Architecture tests**  
   - `testSubscriptBaseDoesNotCreateFolderEdgeOntoUnrelatedProperty` should **pass**.

6. **Regression**  
   - Full CodefaceTests suite green (nested calls, extension members, qualified external hosts, folder scopes, etc.).

7. **Manual smoke** (optional)  
   - Open `Code/App` in Codeface: Basic Types ↛ Codebase Architecture; Architecture → Basic Types remains.

8. **Docs**  
   - Move this file to `Documentation/Tasks/Done/` when fixed; note test names + design summary like bugs 1–5.

---

## Acceptance criteria

- [ ] Swift `parameter` nodes appear as `.declaration` children of functions/inits in the code tree, named by the **internal** binding (not the external label).
- [ ] Parameters bind in the enclosing function/init body scope and are **not** published into folder/root scopes.
- [ ] `testSubscriptBaseDoesNotLinkToUnrelatedProperty` passes.
- [ ] `testSubscriptBaseDoesNotCreateFolderEdgeOntoUnrelatedProperty` passes.
- [ ] Existing linker + architecture + tree tests still pass.
- [ ] No new false folder edges from exporting parameter names globally.

---

## Risk notes

| Risk | Mitigation |
|------|------------|
| Name field extraction picks type text or external label | Dedicated name helper; unit-test `fromLines lines: [String]` and unlabeled `lines: [String]` |
| Tree tests hard-code child order/shape under `function_declaration` | Update expected trees: types nest under `parameter` |
| Parameters clutter architecture UI | Accept for v1; filter later by `kind` if needed |
| Python parity lag | Document as follow-up if not in same PR |
| Subscript still a “call” to the param | Harmless for folders; separate modeling issue |

---

## Suggested PR shape

Single focused PR:

1. Project Swift (and ideally lambda) parameters as declarations.  
2. Tree + linker + architecture tests (symptom tests already present).  
3. Short comment on `LanguageProfile` / linker pointing at body-local bindings and bug 6.

No Architecture edge special-cases. No change to `TreeSitterCodeSymbol` schema required unless we want an explicit attribute for display (`declaration_kind` / kind label via `SymbolKindDisplay`).

---

## Related

- Bug 1 — extension vs type name at root  
- Bug 2 — external use of extension members  
- Bug 3 — same-file use despite duplicate root name (file scopes)  
- Bug 4 — folder scopes / most-local unique binding  
- Bug 5 — nested call references under open call nodes (why subscript under `joined` is visible at all)
