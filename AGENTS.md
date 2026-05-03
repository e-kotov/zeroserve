# Agent Instructions: streamdeck

## Project Overview
`streamdeck` is a high-performance interoperability layer for the R spatial ecosystem. Its primary goal is to provide a comparable experience to Python's `lonboard` by enabling zero-copy binary transport of massive spatial datasets from backends (DuckDB, Arrow) to modern GPU-accelerated frontend renderers (deck.gl via MapLibre).

## Core Mission
We are currently implementing the **Grand Rollout Plan** (see `roadmap.md` for context, though it is untracked). The focus is on building a minimal, robust transport layer without getting bogged down in mapping or styling logic.

## Current Phase
We are starting **Phase 1: Minimal Core Transport**.
- **Objective:** Create `serve_mori()` and `serve_parquet()` APIs.
- **Reference Code:** Existing prototype logic has been moved to `R_drafts/`. Use these files as a source of truth for previously explored implementation details, but aim for a clean, production-ready implementation in the `R/` directory.

## Guiding Principles for Agents
1. **Minimalism:** Stick to the transport layer. Don't re-implement mapping logic that belongs in `mapgl` or `geoarrowDeckglLayers`.
2. **Performance:** Prioritize zero-copy binary paths (Arrow, ALTREP).
3. **TDD:** Follow the project's TDD workflow as defined in `conductor/workflow.md`.
4. **Interoperability:** Ensure the generated URLs work seamlessly with `geoarrowWidget`.
