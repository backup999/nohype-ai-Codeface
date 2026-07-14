# Processor: enum-cases as data store → coexisting pipeline stages

## Status relative to other work

**Partially landed (2026-07-14)** via [Task - Drop DocumentGroup Keep Codebase File](Done/Task%20-%20Drop%20DocumentGroup%20Keep%20Codebase%20File.md):

| Piece | Status |
|-------|--------|
| Durable `CodebaseProcessor.codeFolder` outside the phase enum | **Done** (minimal) — set on successful load/retrieve; not cleared on `.analyzeArchitecture` |
| Export reads that cache (`Export Codebase File…`) | **Done** |
| Session shell (`WindowGroup` / no `FileDocument` handoff) | **Done** |
| Full coexisting stages (`location`, structure, deps, architecture, analysis as sibling fields) | **Still open** (this task) |
| Phase enum shrink to progress/error only | **Still open** |

So: the **export smell for `CodeFolder` is fixed** with a thin side-channel. Generalizing that pattern to all stages remains the job of this task. Do not re-litigate DocumentGroup binding.

## Smell

`CodebaseProcessorState` is a single enum whose **associated values own the pipeline data**. Replacing `state` drops the previous case’s payloads.

Consequences:

- Later stages cannot read earlier outputs unless they re-embed them (or a side channel copies them out).
- After `.analyzeArchitecture`, the raw `CodeFolder` used to vanish from the processor — only UI analysis remained. (**Mitigated today:** durable `codeFolder` cache; export no longer needs the enum.)
- Any new stage (TreeSitter structure IR, deps, …) hits the same wall unless stages coexist as fields.

The enum is fine as a *phase* indicator; it is a poor *sole store* of stage outputs. The existing `codeFolder` cache is the **template** for the remaining fields.

## Target shape

Keep regulation and data separate; let stages coexist:

| Concern | Holds |
|--------|--------|
| **Phase / progress** | Small status (e.g. idle, retrieving, processing, ready, failed) + optional progress copy — *not* the only owner of domain data |
| **Stage outputs** | Parallel optional fields that persist once produced, e.g. `location`, `codeFolder`, later `structure` / `programUnits`, `dependencies`, `architecture`, `analysis` |

Rules of thumb:

1. Advancing the pipeline **writes / updates a stage field**; it does **not** erase sibling stage outputs unless intentionally invalidated.
2. Each stage **reacts to** changes of the previous output (or is driven explicitly after the previous write). Stages can be observed in parallel.
3. **Persistence / export** is boring: `codeFolder` (already durable) is the dump source of truth; **Export Codebase File…** always reads that field when non-nil. No mid-pipeline handoff into a `FileDocument`. Future project-file write paths follow the same rule.
4. UI reads **`analysis`** (and related options) without requiring the enum case to carry every ancestral payload.
5. Successful load-from-file and FS+LSP retrieve both **publish** into the same durable fields (already true for `codeFolder`).

## Non-goals (this change)

- Rewriting treemap / metrics algorithms.
- Full reactive streaming framework; simple stored properties + Observation (or equivalent) are enough.
- Changing the on-disk `.codebase` / `CodeFolder` format.
- Reintroducing `DocumentGroup` / dirty-document lifecycle.
- TreeSitter itself — only the **chassis** for dual backends (see [Integrate TreeSitter Analysis](Task%20-%20Integrate%20TreeSitter%20Analysis.md)).

## Migration sketch

1. **Keep** existing durable `codeFolder` (do not put it back into enum cases just for export).
2. Introduce further durable stage fields on the processor (or a small pipeline model): at least `architecture`, `analysis`; later structure/deps as dual backends land.
3. Shrink the enum to progress/phase (or replace with progress + error only).
4. Wire architecture / analysis as consumers of previous fields rather than sole enum payloads.
5. Invalidate only what successive steps truly replace; leave last-good earlier stages for export/debug until a new successful load/retrieve replaces them (aligns with export cache policy from the DocumentGroup drop task).
6. Remove any residual “must race next phase” comments; export already syncs with `codeFolder`.

## Definition of done (full reform)

- [ ] Phase status does not own savable or multi-stage domain data
- [ ] `codeFolder` remains durable (extend pattern; don’t regress export-after-analysis)
- [ ] Architecture and analysis stages readable without re-embedding ancestors in enum cases
- [ ] Clear invalidation rules on new folder import / file import / reset
- [ ] Ready hooks for optional structure/deps fields (TreeSitter) without another one-off side channel
