>i thought a while about how to start integrating the new treesitter approach into the given app. i came to the conclusion that i should first question the way the app treats codebase files. the current file format is represented by the code in @Code/App/LSP Codebase. the way that raw data is designed is highly specific for the old LSP approach. in particular it stores each symbol's references which we treat as the de facto dependencies and which is basically a dependency cash since getting LSP to work was difficult but when it worked then these references were very accurate. now with the new TreeSitter + our algorithm approach it's the reverse: getting dependencies is cheap but inaccurate and the accuracy will increase fast and with each release, so caching dependencies in a file makes no sense. in the tree sitter approach we will not need a file for the "raw" codebase. at the same time the existing approach already seems to be in tension with SwiftUI's document-based window. the app does not really edit the file, we even throw away the data once we proceed to the analysis stage, and the UX is cumbersome: the user has to first create a new empty file into which he then can "import" a codebase folder which he then cannot even edit. i am not sure why i went the document-based route back then. i t may have been the only way to register a custom file type with macOS so macOS shows our nice .codebase file icon. maybe we can achieve that today without being a document-based window/app. my intuition is: through out the document-based aspect so the app/window matches better the nature of the app, UX already gets streamlined, and then implementing the file-less treesitter approach becomes easier. please analyze this, and in particular: am i applying the "document-based" feature of SwiftUI wrong? Coule we simplify that today? Or should we drop it altogether, and if we drop it do we lose the filetype registration? but please start with a general analysis.
# Analysis: Document-based architecture vs. the real product

1. What the app actually is today

There are three layers that get conflated under the word “codebase”:

┌──────────┬───────────────────────────┬────────────────────────────────┐
│ Layer    │ What it is                │ Role                           │
├──────────┼───────────────────────────┼────────────────────────────────┤
│ Subject  │ A folder of source on     │ The thing the user cares about │
│          │ disk                      │                                │
├──────────┼───────────────────────────┼────────────────────────────────┤
│ Raw      │ CodeFolder / CodeFile /   │ Snapshot of tree + full file   │
│ model    │ CodeSymbol                │ text + LSP symbols and cached  │
│          │                           │ references                     │
├──────────┼───────────────────────────┼────────────────────────────────┤
│ Session  │ Processor → architecture  │ Ephemeral view of that         │
│ / UI     │ artifacts → treemap       │ snapshot                       │
│          │ analysis                  │                                │
└──────────┴───────────────────────────┴────────────────────────────────┘

The document stack wires those together like this:

DocumentGroup → CodebaseFileDocument (optional CodeFolder)
                     │
                     ▼
              CodebaseWindow
                     │
                     ▼
            CodebaseProcessor
              retrieve (FS + LSP) ──publish──► document.codebase  (for Save)
                     │
                     ▼
              architecture / metrics / view models
                     │
                     ▼
              .analyzeArchitecture(analysis)   ← only UI left in state

So the product surface is “analyze this folder,” but the macOS identity of the app is “edit/open a .codebase document.” That mismatch is the root tension you are feeling.

───

2. General analysis of the tension

The .codebase format is an LSP-era dependency cache

The freeze comments on CodeFolder / CodeFile / CodeSymbol are honest: that shape is a stable on-disk dump, not a flexible in-memory IR.

Especially:

• Full source text lives in every CodeFile
• Every CodeSymbol can carry references: [ReferenceLocation] — i.e. precomputed “who depends on me / where am I used”
• Those references are exactly what architecture construction turns into graph edges

That made sense when:

• Getting LSP to work was hard and flaky  
• A successful run was valuable enough to freeze  
• Re-running analysis was expensive  

Under TreeSitter + your algorithms the economics flip:

┌────────────────────┬────────────────┬─────────────────────────────────┐
│                    │ LSP-era        │ TreeSitter-era                  │
├────────────────────┼────────────────┼─────────────────────────────────┤
│ Structure + deps   │ High, brittle  │ Cheap, local                    │
│ cost               │                │                                 │
├────────────────────┼────────────────┼─────────────────────────────────┤
│ Accuracy           │ High when it   │ Lower at first, improving every │
│                    │ works          │ release                         │
├────────────────────┼────────────────┼─────────────────────────────────┤
│ Value of caching   │ High           │ Low / harmful (stale “truth”)   │
│ deps               │                │                                 │
├────────────────────┼────────────────┼─────────────────────────────────┤
│ Natural reload     │ Rare           │ Frequent / on open              │
└────────────────────┴────────────────┴─────────────────────────────────┘

Caching inaccurate-but-improving deps in a user-visible file is worse than no cache: the file becomes a false authority that fights re-analysis.

The app does not behave like a document editor

Even with DocumentGroup + FileDocument, the interaction model is not document editing:

1. New → empty document (“This is an empty codebase file…”)
2. Import folder into that shell
3. Analysis runs; UI shows treemap / code
4. Source is shown with TextEditor(text: .constant(...)) — read-only
5. After analysis, processor state no longer carries CodeFolder (only analysis); saveability depends on a mid-pipeline handoff (publishCodeFolder → document binding)
6. The user does not iteratively edit the .codebase content; they re-import or re-open

That is closer to Instruments, Instruments-style session tools, or “open a project folder and explore” than to TextEdit / Pages / Xcode project editing.

Your own pipeline notes already capture the save/analysis friction: later phases drop the savable payload from the enum, so document save is bolted on with a side channel. That is a symptom of forcing a cache into a document API that expects continuous editable content.

Document-based UX costs you pay today

Because the shell is document-based, launch and menus follow Apple’s document app grammar:

• Cold launch → empty new document or Open panel  
• File → New / Open / Open Recent for .codebase, not for “folders you analyzed”  
• Extra step: create empty file, then import  
• Mental model: “my work is a file I own,” when the real work product is “understanding of this tree”

You already partially compensate with:

• CodebaseLocationPersister (last folder + security-scoped bookmark)  
• “Import … Again”  
• Comments that product conveniences were stripped so DocumentGroup can “own” launch  

So the architecture is fighting itself: document system for identity/menus, ad-hoc persistence for the actual subject (the folder).

Why document-based probably felt right then

Likely motivations (all reasonable at the time):

1. Custom type + Finder icon for .codebase  
2. Cheap multi-window and Open Recent via NSDocumentController  
3. Sandbox-friendly open/save of a single file  
4. LSP snapshot as portable artifact (“send me your .codebase”)  
5. SwiftUI macOS era: DocumentGroup was the blessed multi-window + file path  

None of those require that the payload be a full reference cache forever — but once the type existed, the format and the app scene type fused together.

───

3. Are you “using document-based wrong”?

Short answer: no, not syntactically — yes, ontologically.

What you’re doing “correctly”

• DocumentGroup(newDocument:) + FileDocument is the standard SwiftUI way  
• UTType export + Info.plist document types match  
• Reading/writing via ReadConfiguration / FileWrapper is fine  
• Hiding undo/redo for a non-editing doc is a reasonable adaptation  

Where the fit is wrong

Document-based means: the document is the primary user artifact, continuously editable, saved/restored as the unit of work.

In Codeface:

┌───────────────────────────────┬───────────────────────────────────────┐
│ Document-app assumption       │ Codeface reality                      │
├───────────────────────────────┼───────────────────────────────────────┤
│ User authors document content │ User points at an external folder     │
├───────────────────────────────┼───────────────────────────────────────┤
│ Edits are incremental         │ Analysis is batch pipeline            │
├───────────────────────────────┼───────────────────────────────────────┤
│ Save preserves user work      │ Save preserves analysis cache         │
├───────────────────────────────┼───────────────────────────────────────┤
│ Dirty flag = unsaved edits    │ Dirty = “we re-ran import” (awkward)  │
├───────────────────────────────┼───────────────────────────────────────┤
│ Empty new doc is a blank      │ Empty new doc is a dead end until     │
│ canvas                        │ Import                                │
└───────────────────────────────┴───────────────────────────────────────┘

So this is not a misuse of APIs so much as choosing the wrong product shape for what Codeface is: a codebase analysis session over a folder, not an editor of analysis dumps.

Analogy: if Xcode only opened .xcresult caches and forced you to create an empty result file before “importing” a project, that would feel the same way. The subject is the project; the result file is optional export.

───

4. Can you simplify while keeping document-based?

Yes — if you still want a first-class file, change what the file means, not only polish UX.

Option A — Lightweight project / session document (keep DocumentGroup)

Document content becomes something like:

folder bookmark / path
language / file endings
optional analysis options
(no symbols, no refs, maybe no full source)

Then:

• New document = “new analysis project” with a folder picker as the primary action  
• Save/reopen = restore which codebase and settings, then re-run TreeSitter pipeline  
• .codebase stays a real type with your icon, but stops being a dependency cache  

Pros: Keeps Open Recent, double-click, multi-window document grammar, icon.  
Cons: Still a document-shaped app for something that is essentially a project pointer; empty-doc problem remains unless New immediately runs a folder panel.

Option B — Document is optional export only

Keep analysis session as non-document UI; “Export snapshot…” if you ever need sharing. Heavy for most users; rarely needed with TreeSitter.

Option C — Drop documents entirely (see next)

Best match to “folder is the unit of work.”

Simplifying implementation of the current full-dump document (fix enum→document handoff, dirty state, etc.) does not fix the product mismatch; it only makes the wrong model less buggy.

───

5. If you drop document-based: do you lose filetype registration?

File type registration ≠ DocumentGroup

These are separate mechanisms:

┌────────────────────────────────┬──────────────────────────────────────┐
│ Mechanism                      │ What it does                         │
├────────────────────────────────┼──────────────────────────────────────┤
│ UTExportedTypeDeclarations in  │ Declares com.flowtoolz.codeface.     │
│ Info.plist                     │ codebase and extension codebase (+   │
│                                │ icon via UTTypeIcons)                │
├────────────────────────────────┼──────────────────────────────────────┤
│ CFBundleDocumentTypes          │ Says the app opens/edits/views that  │
│                                │ UTI (role, rank, icon)               │
├────────────────────────────────┼──────────────────────────────────────┤
│ DocumentGroup / NSDocument     │ Runtime: document controller, New/   │
│                                │ Open/Save, dirty, autosave, multi    │
│                                │ -doc windows                         │
└────────────────────────────────┴──────────────────────────────────────┘

You can:

1. Keep registering .codebase without DocumentGroup — app can still open those files via onOpenURL, app delegate, or a custom Open handler, role Viewer or Editor.  
2. Stop exporting the type entirely — then no custom extension/icon for that format; folders remain generic folder icons.  
3. Register as a folder handler — harder and usually wrong; you do not own “folder” as a type in the Finder sense the way you own .codebase.

So:

• Dropping DocumentGroup does not by itself remove custom filetype registration.  
• Dropping the .codebase format does remove the custom document icon and “double-click this analysis file” story.  
• You do not need document-based windows only to show a custom icon: Info.plist UTIs + document type entries (or even a non-document “viewer” role) are enough for Finder association. What you lose without a document stack is free document lifecycle (New/Save/Autosave/Versions/Open Recent for that type), not the ability to claim a UTI.

Practical nuance: if nothing ever creates .codebase files anymore, the icon only matters for legacy files. For a TreeSitter-first product, that may be acceptable (read-only legacy open for one release, then sunset).

───

6. What dropping document-based would unlock

A natural non-document shape:

WindowGroup (or multi-window app model)
  └── Analysis window keyed by folder location
        open folder → security-scoped bookmark
        re-analyze on demand / on focus
        recent folders (your persister, expanded)

UX becomes:

1. Open Codeface → welcome: pick / drop folder (or reopen last)  
2. Analysis runs in-process (TreeSitter)  
3. No empty intermediate file  
4. “Windows” = concurrent analyses of different folders  
5. Optional: File → Open Recent folder, not recent dump  

That matches the TreeSitter economics (recompute cheap) and your mental model (no raw codebase file).

Costs / work:

• Rebuild launch, menus, multi-window focus (you already use @FocusedObject — portable)  
• Own Open Recent / restore yourself (you partially do via CodebaseLocationPersister)  
• Decide legacy .codebase support: import once, ignore refs, or deprecate  
• Lose automatic document dirty/save UI (good — you don’t want it)  

───

7. Recommendation (aligned with TreeSitter, not with sunk cost)

Your intuition is largely right. I’d sharpen it as three separable decisions:

Decision 1 — Stop treating dependency cache as the product artifact  
Yes. For TreeSitter, do not design around saving refs/structure as the user’s file. Recompute. Persist only location + settings (and maybe UI state: last selected path, display options).

Decision 2 — Document-based window  
Prefer dropping DocumentGroup as the primary scene, not because Apple forbids your current use, but because the app is a folder analysis tool, not a document editor. That is the cleanest match to:

• streamlined UX (no empty file → import)  
• file-less TreeSitter pipeline  
• processor that holds stage outputs in memory without serving Save  

You were not “applying DocumentGroup wrong”; you applied a document product model to a non-document product.

Decision 3 — Custom filetype  
• Not required for TreeSitter.  
• Keep only if you want legacy double-click or a lightweight “project” file.  
• Registration can survive without DocumentGroup; the icon story only matters if users still create those files.

Ordering relative to your existing docs

Your Task - Integrate TreeSitter Analysis and processor-reform notes still apply, but with an adjustment:

┌───────────────────────────┬───────────────────────────────────────────┐
│ Earlier plan              │ Revised emphasis                          │
├───────────────────────────┼───────────────────────────────────────────┤
│ Phase 1: durable          │ Phase 1: durable stages for in-memory     │
│ processor stages so       │ pipeline (location, source tree,          │
│ document save tracks      │ structure IR, deps, analysis) — save is   │
│ codeFolder                │ optional/non-goal                         │
├───────────────────────────┼───────────────────────────────────────────┤
│ Keep .codebase as folder  │ Treat .codebase as legacy / optional; don │
│ +text cache “for a long   │ ’t build the new IR around it             │
│ time”                     │                                           │
├───────────────────────────┼───────────────────────────────────────────┤
│ Document handoff as       │ Session + folder location as chassis;     │
│ integration chassis       │ document was the wrong chassis            │
└───────────────────────────┴───────────────────────────────────────────┘

Processor reform remains valuable (enum as sole store is still a smell). Document reform is the larger product unlock for TreeSitter UX — and doing document/session identity first (or together) avoids re-wiring save into a format you’re about to abandon.

───

8. Summary answers to your questions

┌──────────────────┬────────────────────────────────────────────────────┐
│ Question         │ Answer                                             │
├──────────────────┼────────────────────────────────────────────────────┤
│ General          │ App is a folder analyzer forced into a document    │
│ analysis?        │ -cache shell; LSP made the cache rational;         │
│                  │ TreeSitter makes it counterproductive; UX and      │
│                  │ processor already show the strain.                 │
├──────────────────┼────────────────────────────────────────────────────┤
│ Applying         │ APIs used normally; product model is the misfit.   │
│ document-based “ │                                                    │
│ wrong”?          │                                                    │
├──────────────────┼────────────────────────────────────────────────────┤
│ Simplify while   │ Yes: lightweight project file (path + settings),   │
│ keeping it?      │ not full dump — still second-best vs dropping      │
│                  │ docs.                                              │
├──────────────────┼────────────────────────────────────────────────────┤
│ Drop altogether? │ Strong yes as primary architecture for TreeSitter  │
│                  │ -era Codeface.                                     │
├──────────────────┼────────────────────────────────────────────────────┤
│ Lose filetype    │ No if you only drop DocumentGroup and keep UTI/    │
│ registration?    │ document type entries. Yes only if you retire the  │
│                  │ .codebase format (and then you only lose that      │
│                  │ format’s icon/Open association, not the app).      │
└──────────────────┴────────────────────────────────────────────────────┘

If you want a next step, I can sketch a concrete target architecture: WindowGroup + session model, what to persist, legacy .codebase open path, and which types in LSP Codebase die vs. become in-memory IR — still analysis-only, no code changes yet.

--
