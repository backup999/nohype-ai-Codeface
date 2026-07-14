# Task: Drop DocumentGroup (keep `.codebase` + LSP)

## Status

**Implemented** (2026-07-14): `WindowGroup` session app; durable `CodeFolder` cache; File → Import/Export Codebase File; LSP folder path unchanged.

Related:

- [Conversation - DocumentBasedApp.md](Conversation%20-%20DocumentBasedApp.md) — product/architecture analysis
- [Task - ProcessorPipelineArchitecture.md](Task%20-%20ProcessorPipelineArchitecture.md) — enum stage-data smell; this task only needs a **minimal** durable `CodeFolder` cache (not full reform)
- [Task - Integrate TreeSitter Analysis.md](Task%20-%20Integrate%20TreeSitter%20Analysis.md) — later; **do not** couple this migration to TreeSitter

---

## 1. Assumptions check (read first)

### What is correct

| Assumption | Verdict |
|------------|---------|
| First step: drop **document-based window machinery** (`DocumentGroup` / `FileDocument` lifecycle), keep LSP pipeline and current `.codebase` **payload** | **Yes.** Good sequencing. |
| Must not break the LSP pipeline before TreeSitter is integrated and proven | **Yes.** This task is shell/session only. |
| Keep the `.codebase` UTI / extension / icon for product identity and a future project-file purpose | **Yes.** Registration is independent of `DocumentGroup`. |
| Dropping the document *scene* makes a later file-less / project-file model easier | **Yes**, if the window is a session and file I/O is explicit import/export. |
| Reproduce only **bare-minimum** file UI: import a `.codebase` file + export a `.codebase` file | **Yes.** Do **not** rebuild full document chrome. |
| Export needs `CodeFolder` even after analysis; cache it **outside** the processor state enum | **Yes.** Required for this task; see §3. |

### What needs correction

**1. “Just drop DocumentGroup” still means a real scene cutover — but file UX stays thin.**

You replace `DocumentGroup` with `WindowGroup` and re-own only:

- **Import codebase file…** → open panel → decode dump → run processor  
- **Export codebase file…** → save panel → encode cached dump  

You do **not** re-own: Save / Save As, dirty flags, document URL identity, Open Recent, auto-restore, close confirmations, continuous document binding, or Finder-as-document-controller behavior (optional later).

**2. Export will fail with the enum-as-store design unless you cache.**

After `.analyzeArchitecture`, `CodebaseProcessorState` no longer carries `CodeFolder` — only UI analysis. A random File → Export cannot read the dump from `state`.

Already partially mitigated: `CodebaseProcessor.codeFolder` + `publishCodeFolder` (for DocumentGroup). This task **keeps and relies on** that durable cache (or equivalent on the window/session), independent of the phase enum. No full processor reform required — just ensure:

- whenever a `CodeFolder` is successfully loaded or retrieved, it is stored outside the enum  
- export always reads that cache  
- if cache is `nil`, Export is disabled or no-ops with a clear reason  

**3. Import file ≠ import folder.**

Keep both:

| Action | Meaning |
|--------|---------|
| Import **folder** / Swift package / last folder | Existing LSP retrieve path (unchanged) |
| Import **`.codebase` file** | Load dump → `runProcessor(with:)` (skip FS+LSP retrieve) |
| Export **`.codebase` file** | Write cached `CodeFolder` to user-chosen path |

**4. Filetype registration survives; free document menus go away.**

Keep Info.plist UTI + icon. No obligation to implement Open Recent, double-click restore, or system Save. Finder double-click is **out of scope** for the bare minimum (can be a later nicety via `onOpenURL`).

**5. Project-file format and TreeSitter stay later.**

This task freezes the dump schema. Do not shrink the file to a project pointer here.

### Bottom line

Shell migration + **import file / export file** only.  
Durable **`CodeFolder` cache outside the enum** so export works after analysis.  
Not a full document-app reimplementation; not the project-file redesign.

---

## 2. Goals and non-goals

### Goals

1. Primary scene is **`WindowGroup`**, not `DocumentGroup`.
2. Each window is an **analysis session** (`CodebaseWindow`) owning processor + display options.
3. **LSP pipeline unchanged**: locate folder → FS → LSP symbols/refs → architecture → analysis UI.
4. **`.codebase` format unchanged** (full `CodeFolder` dump with symbols/references).
5. **File UI bare minimum:**
   - **Import codebase file…** (open panel → load → process)  
   - **Export codebase file…** (save panel → write cache; enabled only when cache non-nil)  
6. **Durable `CodeFolder` cache** outside `CodebaseProcessorState` so export works in any post-load phase (including `.analyzeArchitecture`).
7. Info.plist UTI + document type + icon **remain** (for future project file + Finder identity).
8. Existing **folder** import actions keep working.
9. Focused-window menus (Find, View, Purchase, folder import) keep working.

### Non-goals (explicit)

- Save / Save As / dirty tracking / “document URL” as live identity  
- Open Recent, launch restore, close-discard prompts  
- Finder double-click / `onOpenURL` (optional later; not required for done)  
- Full processor coexisting-stages reform (only the cache field)  
- TreeSitter / dual backend  
- Schema change of `CodeFolder` / `CodeFile` / `CodeSymbol`  
- Turning `.codebase` into a project pointer  
- iCloud / ubiquitous document activity  

---

## 3. Target architecture

```text
CodefaceApp
  WindowGroup {
      CodebaseWindowView()          // session only; no Binding<FileDocument>
  }
  + About / TestingDashboard

CodebaseWindow
  • codebaseProcessor
  • displayOptions
  • lastLocation (folder)           // existing folder-import helper
  • import/export presentation flags as needed

CodebaseProcessor
  • state: CodebaseProcessorState   // phase + UI payloads (enum can still drop CodeFolder)
  • codeFolder: CodeFolder?         // DURABLE CACHE — export source of truth
       set whenever load/retrieve succeeds; cleared on new empty session / failed reset if desired

File I/O (no FileDocument lifecycle)
  • import: URL → Data → CodeFolder → runProcessor(with:)
  • export: codeFolder! → Data → URL (save panel)
```

### Why the cache is mandatory for bare-minimum export

```text
retrieve / load CodeFolder
        │
        ├─► publish to codeFolder cache   ◄── export always reads here
        │
        ▼
  process → architecture → analyzeArchitecture(analysis)
        │
        └── state no longer holds CodeFolder  (today’s enum design — OK if cache exists)
```

| Source | Usable for Export after analysis? |
|--------|-------------------------------------|
| `state` associated values | **No** (dropped in `.analyzeArchitecture`) |
| `processor.codeFolder` (or session mirror) | **Yes** — this is the plan |
| Re-read from disk | Only if we had a bound document URL — **out of scope** |

Today `publishCodeFolder` already fills `codeFolder` and used to push into `FileDocument`. After migration:

- keep writing the cache on successful retrieve/load  
- drop the document binding callback  
- Export reads `codebaseProcessor.codeFolder` (or a single clear accessor on the window)

Do **not** re-embed `CodeFolder` into every enum case just for export.

### Ownership of dump data

| Before | After |
|--------|--------|
| `FileDocument.codebase` ← processor callback | `processor.codeFolder` (durable) |
| System Save | **Export codebase file…** (save panel, always pick location) |
| System Open / New document | **Import codebase file…** + empty session window; no untitled file |

### What stays in `LSP Codebase/`

| Keep | Role |
|------|------|
| `CodeFolder` / `CodeFile` / `CodeSymbol` | Format + in-memory model (**do not change**) |
| FS + LSP load extensions | Retrieve pipeline |
| Encode/decode | Import/export bytes |
| `UTType.codebase` | Type identity |

| Retire or gut | Role |
|---------------|------|
| `CodebaseFileDocument` as `FileDocument` | Replace with thin load/save helpers (name free) |

---

## 4. Migration phases

### Phase A — Ensure durable cache (small, can land first)

1. Confirm `CodebaseProcessor.codeFolder` is set on **every** successful path that has a dump:
   - after FS+LSP retrieve  
   - when starting from an already-loaded `CodeFolder` (open/import file, or document-era load)  
2. Do **not** clear the cache when transitioning to `.analyzeArchitecture`.  
3. Optional: clear cache when resetting to `.empty` or starting a new folder import (replace with new dump when publish runs).  
4. If still on DocumentGroup briefly: document binding can read the same cache; or skip and go to Phase B.

*This is the entire “processor” work for this task — not full pipeline reform.*

### Phase B — Replace `DocumentGroup` with `WindowGroup`

1. **`CodefaceApp`**
   - `WindowGroup` → `CodebaseWindowView`  
   - Launch: one empty session window (recommended)  
   - Keep About / TestingDashboard  

2. **`CodebaseWindowView`**
   - Drop `Binding<CodebaseFileDocument>`  
   - Session-only `@StateObject`  
   - Keep folder fileImporter + CodebaseLocator + toolbars  

3. **`CodebaseWindow`**
   - Remove `onCodeFolderForDocument`  
   - Add import-file / export-file entry points (panels or flags)  
   - Keep all folder `runProcessor…` APIs  

4. **Menus — bare minimum file I/O only**

   Beside existing folder imports, add (names flexible):

   | Menu item | Behavior |
   |-----------|----------|
   | **Import Codebase File…** | Open panel, `UTType.codebase` / `.codebase`, decode, `runProcessor(with:)` |
   | **Export Codebase File…** | Save panel; encode `processor.codeFolder`; **disabled** if cache is nil |

   Do **not** add: New Document, Open Recent, Save, Save As, Revert, etc.  
   Optional: **New Window** if multi-window is trivial with `WindowGroup` + `openWindow`; not required for file I/O.

5. **I/O helpers**
   - Load: `Data` → `CodeFolder` / optional wrapper (same JSON as today)  
   - Save: `CodeFolder` → `Data` with `.withoutEscapingSlashes` (match current `FileDocument` encode)  
   - Security-scoped access for user-selected URLs under sandbox  

6. **Empty state copy**
   - Session language: import a folder or import a codebase file — not “empty codebase file.”  

7. **Remove `FileDocument` / `DocumentGroup`**
   - Keep UTI declaration in code + Info.plist  

### Phase C — Polish (only if cheap; not required for done)

- Window title from folder name or imported file name (display-only; no dirty state)  
- Info.plist: keep UTI; optional cleanup of ubiquitous document activity  
- Later: Finder double-click via `onOpenURL` (explicitly **not** part of bare minimum)

### Phase D — Verification

- [ ] Cold launch → empty session, no document Open panel forced by NSDocument  
- [ ] Import folder / Swift package / last folder → LSP → treemap (unchanged)  
- [ ] After analysis, **Export** enabled and writes a `.codebase` that re-imports  
- [ ] **Import codebase file** of that export → analysis without re-LSP  
- [ ] **Export** disabled (or harmless) when nothing loaded  
- [ ] Multi-window sessions independent (if multi-window supported)  
- [ ] Focused menus still work  
- [ ] Finder still shows `.codebase` icon (UTI registration)  
- [ ] Sandbox: user-selected import/export paths work  

Regression bar: LSP folder path unchanged; export bytes decode-compatible with current format.

---

## 5. Suggested code touch list

| Area | Likely changes |
|------|----------------|
| `CodefaceApp.swift` | `WindowGroup`; Import/Export file menu items |
| `CodebaseWindowView.swift` | No document binding; optional import/export panels |
| `CodebaseWindow.swift` | Drop document callback; import/export methods |
| `CodebaseFileDocument.swift` | Strip `FileDocument` → load/export helpers |
| `CodebaseProcessor.swift` | Keep/harden `codeFolder` cache; stop document publish callback |
| `EmptyProcesorView.swift` | Copy |
| `Info.plist` | Keep UTI; no new document-controller requirements |

**Do not touch** unless forced by compile:

- `CodeFolder` / `CodeFile` / `CodeSymbol` fields  
- LSP server / architecture / metrics / treemap  
- TreeSitter PoC  

---

## 6. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Export with nothing in memory | Disable menu when `codeFolder == nil` |
| Cache never set on file-import path | Publish cache in the same place for retrieve **and** load-from-file |
| Cache cleared by state transitions | Never store cache only in enum; don’t nil cache on analyze |
| Users expect Save / Open Recent | Accept bare minimum; document in empty state / release notes if needed |
| Format drift on export | Centralize encode options from old `FileDocument` |
| Scope creep (dirty, Finder, project file) | Non-goals list; reject in review |

---

## 7. Ordering vs other work

```text
[This task] WindowGroup + import/export file + durable CodeFolder cache
        │
        ▼
[Optional] Full processor coexisting stages (generalizes the cache pattern)
        │
        ▼
[Later]  .codebase → project file (path + settings)
        │
        ▼
[Later]  TreeSitter path → default flip
```

Note for later TreeSitter docs: “document save tracks `codeFolder`” becomes “session/processor cache; **export** optional.”

---

## 8. Definition of done

- No `DocumentGroup` / no `FileDocument` editing loop.  
- Folder import → LSP → analyze works as today.  
- **Import codebase file** and **Export codebase file** work against the **same dump format**.  
- Export works **after** analysis because `CodeFolder` is cached outside the phase enum.  
- No Save/Open Recent/dirty/Finder-open requirement.  
- UTI/icon retained.  
- No TreeSitter work required.

---

## 9. Implementation order (when executing)

1. Harden `codeFolder` cache on all successful load/retrieve paths; stop relying on enum for export.  
2. Extract encode/decode helpers from `CodebaseFileDocument`.  
3. Swap to `WindowGroup`; drop document binding.  
4. Add Import / Export file menu items + panels; disable Export when cache nil.  
5. Update empty-state copy.  
6. Manual acceptance checklist.  
7. Delete dead `FileDocument` API and document-handoff comments.

---

## 10. Open choices (minor)

1. **Menu labels:** “Import/Export Codebase File…” vs “Import/Export…”  
2. **New Window:** yes/no for v1  
3. **Clear cache** on failed processing vs leave last good dump for export  

None block the architecture. Prefer: leave last good `codeFolder` until a new successful load/retrieve replaces it (so export still works after a later UI-only failure if any).
