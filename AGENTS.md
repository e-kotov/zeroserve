# Agent Instructions: zeroserve

`zeroserve` is a high-performance, frontend-agnostic transport layer for the R ecosystem. Its primary goal is to enable zero-copy binary transport of massive datasets from backends (DuckDB, Arrow, sf) to modern web frontends by serving them over a local HTTP server.


## Core Mission
We are currently implementing the **Grand Rollout Plan** (see `roadmap.md` for context, though it is untracked). The focus is on building a minimal, robust transport layer without getting bogged down in mapping or styling logic.

## Current Phase
We are starting **Phase 1: Minimal Core Transport**.
- **Objective:** Create `zs_serve_arrow()` and `zs_serve_parquet()` APIs.
- **Reference Code:** Existing prototype logic has been moved to `R_drafts/`. Use these files as a source of truth for previously explored implementation details, but aim for a clean, production-ready implementation in the `R/` directory.

## Guiding Principles for Agents
1. **Minimalism:** Stick to the transport layer. Don't re-implement mapping logic that belongs in `mapgl` or `geoarrowDeckglLayers`.
2. **Performance:** Prioritize zero-copy binary paths (Arrow, ALTREP).
3. **TDD:** Follow the project's TDD workflow as defined in `conductor/workflow.md`.
4. **Interoperability:** Ensure the generated URLs work seamlessly with `geoarrowWidget`.
