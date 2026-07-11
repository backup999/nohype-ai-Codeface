# Processor: enum-cases as data store → coexisting pipeline stages

## Smell

`CodebaseProcessorState` is a single enum whose **associated values own the pipeline data**. Replacing `state` drops the previous case’s payloads.

Consequences:

- Later stages cannot read earlier outputs unless they re-embed them (or a side channel copies them out).
- After `.analyzeArchitecture`, the raw savable `CodeFolder` is gone from the processor — only UI analysis remains.
- `DocumentGroup` save only encodes `CodebaseFileDocument.codebase`, which must be filled by a mid-pipeline handoff. Miss that handoff → empty file while visualization still works.

The enum is fine as a *phase* indicator; it is a poor *sole store* of stage outputs.

## Target shape

Keep regulation and data separate; let stages coexist:

| Concern | Holds |
|--------|--------|
| **Phase / progress** | Small status (e.g. idle, retrieving, processing, ready, failed) + optional progress copy — *not* the only owner of domain data |
| **Stage outputs** | Parallel optional fields that persist once produced, e.g. `location`, `codeFolder`, `architecture`, `analysis` |

Rules of thumb:

1. Advancing the pipeline **writes / updates a stage field**; it does **not** erase sibling stage outputs unless intentionally invalidated.
2. Each stage **reacts to** changes of the previous output (or is driven explicitly after the previous write). Stages can be observed in parallel.
3. Save is boring: document `codebase` tracks **`codeFolder`** (or equivalent source of truth) whenever that field is set or updated — not a one-shot event that must race the next phase.
4. UI reads **`analysis`** (and related options) without requiring the enum case to carry every ancestral payload.

## Non-goals (this change)

- Rewriting treemap / metrics algorithms.
- Full reactive streaming framework; simple stored properties + Observation (or equivalent) are enough.
- Changing the on-disk `.codebase` / `CodeFolder` format.

## Migration sketch

1. Introduce durable stage fields on the processor (or a small pipeline model).
2. Shrink the enum to progress/phase (or replace with progress + error only).
3. Wire retrieve → `codeFolder` → document handoff as a normal property update.
4. Wire architecture / analysis steps as consumers of the previous field.
5. Remove residual event-bus / “did just retrieve” bridges once the document stays in sync with `codeFolder`.
